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

import AsyncSwiftIO
import Glibc
import QuadRotary
import SeeSaw
import SwiftIO

@main
public actor SeeSawQuadRotary {
  public static func main() async throws {
    let deviceNumber: Int32? = if CommandLine.arguments.count > 1 {
      Int32(CommandLine.arguments[1])!
    } else {
      nil
    }

    let interruptPin: Int32? = if CommandLine.arguments.count > 2 {
      Int32(CommandLine.arguments[2])!
    } else {
      nil
    }

    let mode: QuadRotary.Mode = if let interruptPin {
      .interrupt(interruptPin)
    } else {
      .poll(QuadRotary.DefaultPollInterval)
    }

    let seeSaw = try await SeeSawQuadRotary(
      deviceNumber: deviceNumber,
      mode: mode
    ) { @Sendable value in
      debugPrint("Rotary \(value)")
    }
    try await seeSaw.run()
  }

  private var quadRotary: QuadRotary
  private var callback: @Sendable (QuadRotary.Event)
    -> ()

  init(
    deviceNumber: Int32? = nil,
    mode: QuadRotary.Mode,
    _ callback: @escaping @Sendable (QuadRotary.Event) -> ()
  ) async throws {
    self.callback = callback
    quadRotary = try await QuadRotary(deviceNumber: deviceNumber ?? 1, mode: mode)
  }

  @SeeSawActor
  func run() async throws {
    await quadRotary.run()
    for try await event in await quadRotary.events {
      await callback(event)
    }
    await quadRotary.stop()
  }
}

#else

@main
public actor SeeSawQuadRotary {
  public static func main() async throws {}
}

#endif
