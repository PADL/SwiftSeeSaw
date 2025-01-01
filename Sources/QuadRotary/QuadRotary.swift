/*
 * Copyright 2023-2025 PADL Software Pty Ltd. All rights reserved.
 *
 * The information and source code contained herein is the exclusive
 * property of PADL Software Pty Ltd and may not be disclosed, examined
 * or reproduced in whole or in part without explicit written authorization
 * from the company.
 */

#if os(Linux)

import AsyncAlgorithms
import AsyncExtensions
import AsyncSwiftIO
import IORing
import LinuxHalSwiftIO
import SeeSaw
import SwiftIO
import SystemPackage

@SeeSawActor
public final class QuadRotary {
  public enum Mode: Sendable {
    case poll(Duration)
    case interrupt(Int32)
  }

  public nonisolated static let NumEncoders = UInt8(4)
  public nonisolated static let DefaultPollInterval: Duration =
    .nanoseconds(UInt64(1_000_000.0 / Float(30)))

  public struct Event: Sendable {
    public let index: UInt8

    public enum Value: Sendable {
      case rotated(Int32)
      case switched(Bool)
    }

    public let value: Value
  }

  private let _mode: Mode
  private let _eventChannel = AsyncThrowingChannel<Event, Error>()
  private var _task: Task<(), Error>?
  private let _interrupt: DigitalIn.EdgeInterruptStream!
  private let _encoders: [IncrementalEncoder]
  private let _switches: [DigitalIO]
  private var _switchStates = [Bool](repeating: false, count: Int(QuadRotary.NumEncoders))

  public var events: AnyAsyncSequence<Event> {
    _eventChannel.eraseToAnyAsyncSequence()
  }

  public init(
    deviceNumber: Int32 = 1,
    mode: Mode = Mode.poll(DefaultPollInterval)
  ) async throws {
    let i2c = I2C(Id(rawValue: deviceNumber))
    let seeSaw = try await SeeSaw(i2c: i2c)
    _mode = mode
    switch _mode {
    case .poll:
      _interrupt = nil
    case let .interrupt(pin):
      for i in 0..<QuadRotary.NumEncoders {
        try seeSaw.enableInterrupt(encoder: UInt8(i))
      }
      _interrupt = DigitalIn(Id(rawValue: pin), mode: .pullDown)
        .risingEdgeInterrupts
    }

    var encoders = [IncrementalEncoder]()
    for i in 0..<QuadRotary.NumEncoders {
      encoders.append(IncrementalEncoder(seeSaw: seeSaw, encoder: i))
    }
    _encoders = encoders

    let switches = [
      DigitalIO(seeSaw: seeSaw, pin: 12),
      DigitalIO(seeSaw: seeSaw, pin: 14),
      DigitalIO(seeSaw: seeSaw, pin: 17),
      DigitalIO(seeSaw: seeSaw, pin: 19),
    ]

    for var aSwitch in switches {
      try await aSwitch.switchToInput(pull: .up)
    }
    _switches = switches
  }

  private func _getLastEvents() async throws -> [Event] {
    var events = [Event]()

    for i in 0..<Int(QuadRotary.NumEncoders) {
      if let newValue = try? await _switches[i].value, newValue != _switchStates[i] {
        _switchStates[i] = newValue
        events.append(Event(index: UInt8(i), value: .switched(newValue)))
      }
    }

    for encoder in _encoders {
      if let delta = try? await encoder.delta, delta != 0 {
        events.append(Event(index: encoder.index, value: .rotated(delta)))
      }
    }

    return events
  }

  private func _sendEvents() async {
    for event in await (try? _getLastEvents()) ?? [] {
      await _eventChannel.send(event)
    }
  }

  public func run() {
    _task = Task<(), Error> { @Sendable [self] in
      switch _mode {
      case let .poll(pollInterval):
        repeat {
          await _sendEvents()
          try await Task.sleep(for: pollInterval)
        } while true
      case .interrupt:
        for try await _ in _interrupt! {
          await _sendEvents()
        }
      }
    }
  }

  public func stop() {
    _task?.cancel()
    _task = nil
  }

  deinit {
    _task?.cancel()
  }
}

#endif
