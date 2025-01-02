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
@preconcurrency
import SwiftIO

let Crickit_Pinmap = SeeSaw.PinMap(
  analogPins: [2, 3, 40, 41, 11, 10, 9, 8],
  pwmWidth: 16,
  pwmPins: [14, 15, 16, 17, 18, 19, 22, 23, 42, 43, 12, 13],
  touchPins: [4, 5, 6, 7]
)

let MM1_Pinmap = SeeSaw.PinMap(
  analogPins: [34, 35],
  pwmWidth: 16,
  pwmPins: [8, 9, 10, 11, 16, 17, 18, 19, 40, 41, 42, 43],
  touchPins: [4, 5, 6, 7]
)

let ATtiny8x7_Pinmap = SeeSaw.PinMap(
  analogPins: [0, 1, 2, 3, 6, 7, 18, 19, 20],
  pwmWidth: 16,
  pwmPins: [0, 1, 9, 12, 13, 6, 7, 8],
  touchPins: []
)

let ATtinyx16_Pinmap = SeeSaw.PinMap(
  analogPins: [0, 1, 2, 3, 4, 5, 14, 15, 16],
  pwmWidth: 16,
  pwmPins: [0, 1, 7, 11, 16, 4, 5, 6],
  touchPins: []
)

let SAMD09_Pinmap = SeeSaw.PinMap(
  analogPins: [2, 3, 4, 5],
  pwmWidth: 8,
  pwmPins: [4, 5, 6, 7],
  touchPins: []
)

@globalActor
public actor SeeSawActor {
  public static let shared = SeeSawActor()
}

@SeeSawActor
public final class SeeSaw: CustomStringConvertible {
  public struct PinMap: Sendable {
    public var analogPins: [UInt8]
    public var pwmWidth: UInt8
    public var pwmPins: [UInt8]
    public var touchPins: [UInt8]
  }

  enum BaseAddress: UInt8 {
    case status = 0x00
    case gpio = 0x01
    case sercom0 = 0x02
    case timer = 0x08
    case adc = 0x09
    case dac = 0x0A
    case interrupt = 0x0B
    case dap = 0x0C
    case eeprom = 0x0D
    case neoPixel = 0x0E
    case touch = 0x0F
    case encoder = 0x11
  }

  enum GPIOCommand: UInt8 {
    case dirSetBulk = 0x02
    case dirClrBulk = 0x03
    case bulk = 0x04
    case bulkSet = 0x05
    case bulkClr = 0x06
    case bulkToggle = 0x07
    case intenSet = 0x08
    case intenClr = 0x09
    case intFlag = 0x0A
    case pullEnSet = 0x0B
    case pullEnClr = 0x0C
  }

  enum StatusCommand: UInt8 {
    case hwID = 0x01
    case version = 0x02
    case options = 0x03
    case temp = 0x04
    case swRst = 0x7F
  }

  enum TimerCommand: UInt8 {
    case status = 0x00
    case pwm = 0x01
    case freq = 0x02
  }

  enum ADCCommand: UInt8 {
    case status = 0x00
    case inten = 0x02
    case intenClr = 0x03
    case winMode = 0x04
    case winThresh = 0x05
    case channelOffset = 0x07
  }

  enum SerComCommand: UInt8 {
    case status = 0x00
    case inten = 0x02
    case intenClr = 0x03
    case baud = 0x04
    case data = 0x05
  }

  enum NeoPixelCommand: UInt8 {
    case status = 0x00
    case pin = 0x01
    case speed = 0x02
    case bufLength = 0x03
    case buf = 0x04
    case show = 0x05
  }

  enum TouchCommand: UInt8 {
    case channelOffset = 0x10
  }

  enum EncoderCommand: UInt8 {
    case status = 0x00
    case intenSet = 0x10
    case intenClr = 0x20
    case position = 0x30
    case delta = 0x40
  }

  enum ChipID: UInt8 {
    case samD09 = 0x55
    case atTiny806 = 0x84
    case atTiny807 = 0x85
    case atTiny816 = 0x86
    case atTiny817 = 0x87
    case atTiny1616 = 0x88
    case atTiny1617 = 0x89
  }

  enum ProductID: UInt32 {
    case _crickit = 9999
    case _roboHatMM1 = 9998
    case _5690 = 5690
    case _5681 = 5681
    case _5743 = 5743
  }

  public enum SeeSawError: Error, Sendable {
    case invalidAnalogPin
    case invalidEncoder
    case invalidPWMPin
    case invalidTouchPin
    case unknownChipID
    case unknownProductID
  }

  public enum Mode: Sendable {
    case input
    case inputPullUp
    case inputPullDown
    case output

    var isInput: Bool {
      self != .output
    }

    var hasPull: Bool {
      isInput && self != .input
    }
  }

  private let i2c: I2C
  #if canImport(AsyncSwiftIO)
  private let asyncI2C: AsyncI2C
  #endif
  private let address: UInt8
  private var chipID: ChipID!
  private var pinMapping: PinMap?

  public init(i2c: I2C, address: UInt8 = 0x49, reset: Bool = true) async throws {
    self.i2c = i2c
    #if canImport(AsyncSwiftIO)
    asyncI2C = try await AsyncI2C(
      with: self.i2c,
      address: address,
      blockSize: MemoryLayout<UInt64>.stride
    )
    #endif
    self.address = address
    chipID = try await _getChipID()

    if reset {
      try await swReset()
    }

    if let pid = try _getPID() {
      if pid == ._crickit {
        pinMapping = Crickit_Pinmap
      } else if pid == ._roboHatMM1 {
        pinMapping = MM1_Pinmap
      } else if (pid == ._5690 || pid == ._5681 || pid == ._5743) ||
        (chipID == .atTiny816 || chipID == .atTiny806 || chipID == .atTiny1616)
      {
        pinMapping = ATtinyx16_Pinmap
      }
    } else {
      if chipID == .samD09 {
        pinMapping = SAMD09_Pinmap
      } else if chipID == .atTiny817 || chipID == .atTiny807 || chipID == .atTiny1617 {
        pinMapping = ATtiny8x7_Pinmap
      }
    }
  }

  public nonisolated var description: String {
    "\(type(of: self))(address: \(address))"
  }

  private func _getChipID() async throws -> ChipID {
    guard let chipID =
      try await ChipID(rawValue: read8(base: .status, reg: StatusCommand.hwID.rawValue))
    else {
      throw SeeSawError.unknownChipID
    }
    return chipID
  }

  /// Trigger a software reset of the SeeSaw chip
  public func swReset(postResetDelay: Duration? = .seconds(0.5)) async throws {
    try write8(base: .status, reg: StatusCommand.swRst.rawValue, value: 0xFF)
    if let postResetDelay {
      try await Task.sleep(for: postResetDelay)
    }
  }

  /// Retrieve the 'options' word from the SeeSaw board
  public func getOptions() throws -> UInt32 {
    var buffer = [UInt8](repeating: 0, count: 4)
    try read(base: .status, reg: StatusCommand.options.rawValue, into: &buffer)
    return UInt32(bigEndianBytes: buffer)
  }

  /// Retrieve the 'version' word from the SeeSaw board
  public func getVersion() throws -> UInt32 {
    var buffer = [UInt8](repeating: 0, count: 4)
    try read(base: .status, reg: StatusCommand.version.rawValue, into: &buffer)
    return UInt32(bigEndianBytes: buffer)
  }

  private func _getPID() throws -> ProductID? {
    try ProductID(rawValue: getVersion() >> 16)
  }

  /// Return the EEPROM address used to store I2C address
  private func _getEepromI2CAddr() throws -> UInt8 {
    switch chipID! {
    case .atTiny806:
      fallthrough
    case .atTiny807:
      fallthrough
    case .atTiny816:
      fallthrough
    case .atTiny817:
      return 0x7F
    case .atTiny1616:
      fallthrough
    case .atTiny1617:
      return 0xFF
    case .samD09:
      return 0x3F
    }
  }

  public func setI2CAddr(addr: UInt8) throws {
    try eepromWrite8(addr: _getEepromI2CAddr(), value: addr)
  }

  public func getI2CAddr() throws -> UInt8 {
    try eepromRead8(addr: _getEepromI2CAddr())
  }

  /// Write a single byte directly to the device's EEPROM
  public func eepromWrite8(addr: UInt8, value: UInt8) throws {
    try eepromWrite(addr: addr, [value])
  }

  /// Write multiple bytes directly to the device's EEPROM
  public func eepromWrite(addr: UInt8, _ buffer: [UInt8]) throws {
    try write(base: .eeprom, reg: addr, buffer)
  }

  /// Read a single byte directly to the device's EEPROM
  public func eepromRead8(addr: UInt8) throws -> UInt8 {
    try read8(base: .eeprom, reg: addr)
  }

  /// Set the serial baudrate of the device
  public func uartSetBaud(_ baud: UInt32) throws {
    try write(base: .sercom0, reg: SerComCommand.baud.rawValue, baud.bigEndianBytes)
  }
}

// MARK: - synchronous I/O

extension SeeSaw {
  /// Read an arbitrary I2C register range on the device
  func read(base: BaseAddress, reg: UInt8, into buffer: inout [UInt8]) throws {
    try i2c.writeRead([base.rawValue, reg], into: &buffer, address: address).get()
  }

  /// Read an arbitrary I2C byte register on the device
  func read8(base: BaseAddress, reg: UInt8) throws -> UInt8 {
    var buffer = [UInt8](repeating: 0, count: 1)
    try read(base: base, reg: reg, into: &buffer)
    return buffer[0]
  }

  func read16(base: BaseAddress, reg: UInt8) throws -> UInt16 {
    var buffer = [UInt8](repeating: 0, count: MemoryLayout<UInt16>.stride)
    try read(base: base, reg: reg, into: &buffer)
    return UInt16(bigEndianBytes: buffer)
  }

  func read32(base: BaseAddress, reg: UInt8) throws -> UInt32 {
    var buffer = [UInt8](repeating: 0, count: MemoryLayout<UInt32>.stride)
    try read(base: base, reg: reg, into: &buffer)
    return UInt32(bigEndianBytes: buffer)
  }

  func read64(base: BaseAddress, reg: UInt8) throws -> UInt64 {
    var buffer = [UInt8](repeating: 0, count: MemoryLayout<UInt64>.stride)
    try read(base: base, reg: reg, into: &buffer)
    return UInt64(bigEndianBytes: buffer)
  }

  /// Write an arbitrary I2C register range on the device
  func write(base: BaseAddress, reg: UInt8, _ buffer: [UInt8]? = nil) throws {
    var fullBuffer = [base.rawValue, reg]
    if let buffer { fullBuffer += buffer }
    try i2c.write(fullBuffer, to: address).get()
  }

  /// Write an arbitrary I2C byte register on the device
  func write8(base: BaseAddress, reg: UInt8, value: UInt8) throws {
    try write(base: base, reg: reg, [value])
  }

  func write16(base: BaseAddress, reg: UInt8, _ value: UInt16) throws {
    try write(base: base, reg: reg, value.bigEndianBytes)
  }

  func write32(base: BaseAddress, reg: UInt8, _ value: UInt32) throws {
    try write(base: base, reg: reg, value.bigEndianBytes)
  }

  func write64(base: BaseAddress, reg: UInt8, _ value: UInt64) throws {
    try write(base: base, reg: reg, value.bigEndianBytes)
  }
}

// MARK: - asynchronous I/O

#if canImport(AsyncSwiftIO)

extension SeeSaw {
  /// Read an arbitrary I2C register range on the device asynchronously
  func read(base: BaseAddress, reg: UInt8, count: Int) async throws -> [UInt8] {
#if false
    var block = [UInt8](unsafeUninitializedCapacity: count) { buffer,
      initializedCount in
      buffer[0] = reg
      initializedCount = 1
    }

    try await asyncI2C.writeRead(&block, writeCount: 1, readCount: count)
    return block
#else
  try await write(base: base, reg: reg)
  return try await asyncI2C.read(count)
#endif
  }

  func read8(base: BaseAddress, reg: UInt8) async throws -> UInt8 {
    try await write(base: base, reg: reg)
    return try await asyncI2C.read(1)[0]
  }

  func read16(base: BaseAddress, reg: UInt8) async throws -> UInt16 {
    try await write(base: base, reg: reg)
    return try await UInt16(bigEndianBytes: asyncI2C.read(MemoryLayout<UInt16>.stride))
  }

  func read32(base: BaseAddress, reg: UInt8) async throws -> UInt32 {
    try await write(base: base, reg: reg)
    return try await UInt32(bigEndianBytes: asyncI2C.read(MemoryLayout<UInt32>.stride))
  }

  func read64(base: BaseAddress, reg: UInt8) async throws -> UInt64 {
    try await write(base: base, reg: reg)
    return try await UInt64(bigEndianBytes: asyncI2C.read(MemoryLayout<UInt64>.stride))
  }

  /// Write an arbitrary I2C register range on the device asynchronously
  func write(base: BaseAddress, reg: UInt8, _ buffer: [UInt8]? = nil) async throws {
    var fullBuffer = [base.rawValue, reg]
    if let buffer { fullBuffer += buffer }
    _ = try await asyncI2C.write(fullBuffer)
  }

  func write8(base: BaseAddress, reg: UInt8, _ value: UInt8) async throws {
    let buffer = [base.rawValue, value]
    _ = try await asyncI2C.write(buffer)
  }

  func write16(base: BaseAddress, reg: UInt8, _ value: UInt16) async throws {
    let buffer = [base.rawValue, reg] + value.bigEndianBytes
    _ = try await asyncI2C.write(buffer)
  }

  func write32(base: BaseAddress, reg: UInt8, _ value: UInt32) async throws {
    let buffer = [base.rawValue, reg] + value.bigEndianBytes
    _ = try await asyncI2C.write(buffer)
  }

  func write64(base: BaseAddress, reg: UInt8, _ value: UInt64) async throws {
    let buffer = [base.rawValue, reg] + value.bigEndianBytes
    _ = try await asyncI2C.write(buffer)
  }
}

#endif

// MARK: - general API

public extension SeeSaw {
  /// Set the mode of a pin by number
  func digitalModeSet(pin: UInt8, mode: Mode) async throws {
    try await digitalModeSetBulk(pins: 1 << pin, mode: mode)
  }

  /// Set the value of an output pin by number
  func digitalWrite(pin: UInt8, value: Bool) async throws {
    try await digitalWriteBulk(pins: 1 << pin, value: value)
  }

  /// Get the value of an input pin by number
  func digitalRead(pin: UInt8) async throws -> Bool {
    try await digitalReadBulk(pins: 1 << pin) != 0
  }

  /// Get the value of pins as a bitmask
  func digitalReadBulk(pins: UInt64) async throws -> UInt64 {
    let value = try await read64(base: .gpio, reg: GPIOCommand.bulk.rawValue)
    return value & pins
  }

  /// Enable or disable the GPIO interrupt
  func setGPIOInterrupts(pins: UInt32, enabled: Bool) async throws {
    let cmd = pins.bigEndianBytes
    if enabled {
      try await write(base: .gpio, reg: GPIOCommand.intenSet.rawValue, cmd)
    } else {
      try await write(base: .gpio, reg: GPIOCommand.intenClr.rawValue, cmd)
    }
  }

  /// Read and clear GPIO interrupts that have fired
  func getGPIOInterruptFlag() async throws -> UInt32 {
    try await read32(base: .gpio, reg: GPIOCommand.intFlag.rawValue)
  }

  private func _getAnalogPinOffset(_ pin: UInt8) throws -> UInt8 {
    guard let pinMapping, let offset = pinMapping.analogPins.firstIndex(of: pin) else {
      throw SeeSawError.invalidAnalogPin
    }
    return if chipID == .samD09 {
      UInt8(offset)
    } else {
      pin
    }
  }

  private func _getPWMPinOffset(_ pin: UInt8) throws -> UInt8 {
    guard let pinMapping, let offset = pinMapping.pwmPins.firstIndex(of: pin) else {
      throw SeeSawError.invalidPWMPin
    }
    return if chipID == .samD09 {
      UInt8(offset)
    } else {
      pin
    }
  }

  /// Read the value of an analog pin by number
  func analogRead(pin: UInt8) async throws -> UInt16 {
    let offset = try _getAnalogPinOffset(pin)
    return try await read16(base: .touch, reg: TouchCommand.channelOffset.rawValue + offset)
  }

  /// Read the value of a touch pin by number
  func touchRead(pin: UInt8) async throws -> UInt16 {
    guard let pinMapping, let offset = pinMapping.touchPins.firstIndex(of: pin) else {
      throw SeeSawError.invalidTouchPin
    }

    return try await read16(base: .touch, reg: TouchCommand.channelOffset.rawValue + UInt8(offset))
  }

  /// Set the mode of all the pins as a bitmask
  func digitalModeSetBulk(pins: UInt64, mode: Mode) async throws {
    let cmd = pins.bigEndianBytes

    try await write(base: .gpio, reg: GPIOCommand.dirSetBulk.rawValue, cmd)
    if mode == .output {
      try await write(base: .gpio, reg: GPIOCommand.dirSetBulk.rawValue, cmd)
    } else {
      try await write(base: .gpio, reg: GPIOCommand.dirClrBulk.rawValue, cmd)

      if mode.hasPull {
        try await write(base: .gpio, reg: GPIOCommand.pullEnSet.rawValue, cmd)
        if mode == .inputPullUp {
          try await write(base: .gpio, reg: GPIOCommand.bulkSet.rawValue, cmd)
        } else {
          try await write(base: .gpio, reg: GPIOCommand.bulkClr.rawValue, cmd)
        }
      } else {
        try await write(base: .gpio, reg: GPIOCommand.pullEnClr.rawValue, cmd)
      }
    }
  }

  /// Set the value of pins as a bitmask
  func digitalWriteBulk(pins: UInt64, value: Bool) async throws {
    let cmd = pins.bigEndianBytes
    if value {
      try await write(base: .gpio, reg: GPIOCommand.bulkSet.rawValue, cmd)
    } else {
      try await write(base: .gpio, reg: GPIOCommand.bulkClr.rawValue, cmd)
    }
  }

  /// Set the value of an analog output by number
  func analogWrite(pin: UInt8, value: UInt16) async throws {
    let offset = try _getAnalogPinOffset(pin)
    let cmd: [UInt8] = if pinMapping!.pwmWidth == 16 {
      [offset] + value.bigEndianBytes
    } else {
      [offset, UInt8(value & 0xFF)]
    }
    try await write(base: .timer, reg: TimerCommand.pwm.rawValue, cmd)
    try await Task.sleep(for: .milliseconds(1))
  }

  /// Read the temperature
  func getTemperature() async throws -> Float {
    var value = try await read32(base: .status, reg: StatusCommand.temp.rawValue)
    value &= 0x3F00_0000
    try await Task.sleep(for: .milliseconds(5))
    return 0.00001525878 * Float(value)
  }

  /// Set the PWM frequency of a pin by number
  func setPWM(pin: UInt8, frequency: UInt16) throws {
    let offset = try _getPWMPinOffset(pin)
    let cmd = [offset] + frequency.bigEndianBytes
    try write(base: .timer, reg: TimerCommand.freq.rawValue, cmd)
  }

  private func _validate(encoder: UInt8) throws {
    guard encoder < 0xF else { throw SeeSawError.invalidEncoder }
  }

  /// The current position of the encoder
  func getPosition(of encoder: UInt8 = 0) throws -> Int32 {
    try _validate(encoder: encoder)
    var buffer = [UInt8](repeating: 0, count: 4)
    try read(base: .encoder, reg: EncoderCommand.position.rawValue + encoder, into: &buffer)
    return Int32(bigEndianBytes: buffer)
  }

  /// The current position of the encoder
  func getPosition(of encoder: UInt8 = 0) async throws -> Int32 {
    try _validate(encoder: encoder)
    let ret = try await read32(base: .encoder, reg: EncoderCommand.position.rawValue + encoder)
    return Int32(bitPattern: ret)
  }

  /// Set the current position of the encoder
  func setPosition(of encoder: UInt8 = 0, to position: Int32) throws {
    try _validate(encoder: encoder)
    try write(
      base: .encoder,
      reg: EncoderCommand.position.rawValue + encoder,
      position.bigEndianBytes
    )
  }

  /// Set the current position of the encoder
  func setPosition(of encoder: UInt8 = 0, to position: Int32) async throws {
    try _validate(encoder: encoder)
    try await write32(
      base: .encoder,
      reg: EncoderCommand.position.rawValue + encoder,
      UInt32(bitPattern: position)
    )
  }

  /// The change in encoder position since it was last read
  func getDelta(of encoder: UInt8 = 0) throws -> Int32 {
    try _validate(encoder: encoder)
    var buffer = [UInt8](repeating: 0, count: 4)
    try read(base: .encoder, reg: EncoderCommand.delta.rawValue + encoder, into: &buffer)
    return Int32(bigEndianBytes: buffer)
  }

  /// The change in encoder position since it was last read
  func getDelta(of encoder: UInt8 = 0) async throws -> Int32 {
    try _validate(encoder: encoder)
    return try await Int32(bitPattern: read32(
      base: .encoder,
      reg: EncoderCommand.delta.rawValue + encoder
    ))
  }

  /// Enable the interrupt to fire when the encoder changes position
  func enableInterrupt(encoder: UInt8 = 0) throws {
    try _validate(encoder: encoder)
    try write8(base: .encoder, reg: EncoderCommand.intenSet.rawValue + encoder, value: 1)
  }

  /// Disable the interrupt from firing when the encoder changes
  func disableInterrupt(encoder: UInt8 = 0) throws {
    try _validate(encoder: encoder)
    try write8(base: .encoder, reg: EncoderCommand.intenClr.rawValue + encoder, value: 1)
  }
}

extension FixedWidthInteger {
  init<I>(bigEndianBytes iterator: inout I)
    where I: IteratorProtocol, I.Element == UInt8
  {
    self = stride(from: 8, to: Self.bitWidth + 8, by: 8).reduce(into: 0) {
      $0 |= Self(truncatingIfNeeded: iterator.next()!) &<< (Self.bitWidth - $1)
    }
  }

  init(bigEndianBytes bytes: some Collection<UInt8>) {
    precondition(bytes.count == (Self.bitWidth + 7) / 8)
    var iter = bytes.makeIterator()
    self.init(bigEndianBytes: &iter)
  }

  var bigEndianBytes: [UInt8] {
    let count = Self.bitWidth / 8
    var bigEndian = bigEndian
    return [UInt8](withUnsafePointer(to: &bigEndian) {
      $0.withMemoryRebound(to: UInt8.self, capacity: count) {
        UnsafeBufferPointer(start: $0, count: count)
      }
    })
  }

  func serialize(into bytes: inout [UInt8]) throws {
    bytes += bigEndianBytes
  }
}

#endif
