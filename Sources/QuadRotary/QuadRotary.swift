/*
 * Copyright (c) 2025 PADL Software Pty Ltd
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
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
      case switchPressed
      case switchReleased
    }

    public let value: Value
  }

  private let _mask: UInt8
  private let _mode: Mode
  private let _eventChannel = AsyncThrowingChannel<Event, Error>()
  private var _task: Task<(), Error>?
  private let _interrupt: DigitalIn.EdgeInterruptStream!
  private let _encoders: [IncrementalEncoder]
  private var _encoderPositions = [Int32](repeating: 0, count: Int(QuadRotary.NumEncoders))
  private let _switches: [DigitalIO]
  private var _switchStates = [Bool](repeating: true, count: Int(QuadRotary.NumEncoders))

  public var events: AnyAsyncSequence<Event> {
    _eventChannel.eraseToAnyAsyncSequence()
  }

  public init(
    deviceNumber: Int32 = 1,
    mask: UInt8 = 0xF,
    mode: Mode = Mode.poll(DefaultPollInterval)
  ) async throws {
    let i2c = I2C(Id(rawValue: deviceNumber))
    let seeSaw = try await SeeSaw(i2c: i2c)
    _mask = mask
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
      guard _mask & (1 << i) != 0 else { continue }

      if let newValue = try? await _switches[i].value, newValue != _switchStates[i] {
        _switchStates[i] = newValue
        // switch is pressed when value is `false`
        events.append(.init(index: UInt8(i), value: newValue ? .switchReleased : .switchPressed))
      }

      if let newValue = try? await _encoders[i].getPosition(), newValue != _encoderPositions[i] {
        let delta = newValue - _encoderPositions[i]
        _encoderPositions[i] = newValue
        events.append(.init(index: UInt8(i), value: .rotated(delta)))
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
