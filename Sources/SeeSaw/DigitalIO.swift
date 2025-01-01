/*
 * Copyright (c) 2025 PADL Software Pty Ltd
 * Copyright (c) 2017 Dean Miller for Adafruit Industries
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

#if canImport(AsyncSwiftIO)
import AsyncSwiftIO
#endif
import LinuxHalSwiftIO
import SwiftIO

@SeeSawActor
public struct DigitalIO {
  public enum DriveMode: Sendable {
    case pushPull
    case openDrain
  }

  public enum Direction: Sendable {
    case input
    case output
  }

  public enum Pull: Sendable {
    case up
    case down
  }

  public init(seeSaw: SeeSaw, pin: UInt8) {
    _seeSaw = seeSaw
    _pin = pin
  }

  private let _seeSaw: SeeSaw
  private let _pin: UInt8
  private var _driveMode = DriveMode.pushPull
  private var _direction = Direction.input
  private var _pull: Pull?
  private var _value = false

  public mutating func switchToOutput(
    value: Bool = false,
    driveMode: DriveMode = .pushPull
  ) async throws {
    try await _seeSaw.digitalModeSet(pin: _pin, mode: .output)
    try await _seeSaw.digitalWrite(pin: _pin, value: value)
    _driveMode = driveMode
    _pull = nil
    _direction = .output
  }

  public mutating func switchToInput(pull: Pull? = nil) async throws {
    if pull == .down {
      try await _seeSaw.digitalModeSet(pin: _pin, mode: .inputPullDown)
    } else if pull == .up {
      try await _seeSaw.digitalModeSet(pin: _pin, mode: .inputPullUp)
    } else {
      try await _seeSaw.digitalModeSet(pin: _pin, mode: .input)
    }
    _pull = pull
    _direction = .input
  }

  public var direction: Direction {
    _direction
  }

  public mutating func set(direction: Direction) async throws {
    if direction == .input { try await switchToInput() }
    else { try await switchToOutput() }
  }

  public var value: Bool {
    get async throws {
      if _direction == .output {
        _value
      } else {
        try await _seeSaw.digitalRead(pin: _pin)
      }
    }
  }

  public mutating func set(value: Bool) async throws {
    try await _seeSaw.digitalWrite(pin: _pin, value: value)
    _value = value
  }

  public var driveMode: DriveMode {
    _driveMode
  }

  public var pull: Pull? {
    _pull
  }
}

#endif
