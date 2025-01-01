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
public struct IncrementalEncoder {
  private let _seeSaw: SeeSaw
  private let _encoder: UInt8

  public init(seeSaw: SeeSaw, encoder: UInt8) {
    _seeSaw = seeSaw
    _encoder = encoder
  }

  public var position: Int32? {
    get {
      try? _seeSaw.getPosition(of: _encoder)
    }

    set {
      if let newValue {
        try? _seeSaw.setPosition(of: _encoder, to: newValue)
      }
    }
  }

  public var delta: Int32 {
    get async throws {
      try await _seeSaw.getDelta(of: _encoder)
    }
  }

  public var index: UInt8 {
    _encoder
  }
}

#endif
