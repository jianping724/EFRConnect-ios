//
//  SILRangeTestAppViewModel.swift
//  SiliconLabsApp
//
//  Created by Piotr Sarna on 04.06.2018.
//  Copyright © 2018 SiliconLabs. All rights reserved.
//

import UIKit

protocol SILRangeTestAppViewModelDelegate {
    func didReceiveAllPeripheralValues()
    
    func updated(setting: SILRangeTestSetting)
    func updated(isTestStarted: Bool)
    func updated(isPacketRepeatEnabled: Bool)
    func updated(isUartLogEnabled: Bool)
    
    func updated(rssi: Int)
    func updated(rx: Int, totalRx: Int, per: Float, ma: Float)
    
    func updated(rx: Int)
    func updated(totalRx: Int)
    func updated(totalTx: Int)
    func updated(ma: Float)
    func updated(per: Float)
}

@objcMembers
class SILRangeTestAppViewModel : NSObject, SILRangeTestPeripheralDelegate {
    private let model: [SILRangeTestSetting: SILRangeTestSettingValue] = [
        .txPower: SILRangeTestSettingValue(title: "TX Power", values: [0], stringFormat: "%gdBm"),
        .payloadLength: SILRangeTestSettingValue(title: "Payload Length", values: [0]),
        .maWindowSize: SILRangeTestSettingValue(title: "MA Window Size", values: [0]),
        .channelNumber: SILRangeTestSettingValue(title: "Channel Number", values: [0]),
        .packetCount: SILRangeTestSettingValue(title: "Packet Count", values: [500, 1_000, 2_500, 5_000, 10_000, 25_000, 50_000]),
        .remoteId: SILRangeTestSettingValue(title: "Remote ID", values: [0]),
        .selfId: SILRangeTestSettingValue(title: "Self ID", values: [0]),
        .phyConfig: SILRangeTestSettingValue(title: "PHY Configuration", values: [0], stringValues: ["<undefined>"])
        ]
    
    private var receivedPeripheralValues = 0 {
        didSet {
            didReceivedAllPeripheralValues = receivedPeripheralValues == SILRangeTestSetting.all.rawValue
        }
    }
    
    private(set) var didReceivedAllPeripheralValues = false {
        didSet {
            if oldValue != didReceivedAllPeripheralValues && didReceivedAllPeripheralValues {
                delegate?.didReceiveAllPeripheralValues()
            }
        }
    }
    
    let peripheral: SILRangeTestPeripheral
    let mode: SILRangeTestMode
    let boardInfo: SILRangeTestBoardInfo
    var delegate: SILRangeTestAppViewModelDelegate?
    var maCalculator: SILRangeTestMovingAverageCalculator?
    var txValueUpdater: SILRangeTestTXValueUpdater?
    
    var isTestStarted = false {
        didSet {
            if oldValue != isTestStarted {
                peripheral.setIsRunning(isTestStarted)
                
                if isTestStarted {
                    startTest()
                } else {
                    stopTest()
                }
            }
            
            delegate?.updated(isTestStarted: isTestStarted)
        }
    }
    
    var isPacketRepeatEnabled = false {
        didSet {
            if oldValue != isPacketRepeatEnabled {
                let packetCount = isPacketRepeatEnabled ? Double(UInt16.max) : getValue(forSetting: .packetCount)
                
                peripheral.setPacketCount(packetCount)
            }
            
            delegate?.updated(isPacketRepeatEnabled: isPacketRepeatEnabled)
        }
    }
    
    var isUartLogEnabled = false {
        didSet {
            if oldValue != isUartLogEnabled {
                peripheral.setUartLogEnabled(isUartLogEnabled)
            }
            
            delegate?.updated(isUartLogEnabled: isUartLogEnabled)
        }
    }
    
    init(withMode mode: SILRangeTestMode, peripheral: SILRangeTestPeripheral, andBoardInfo boardInfo: SILRangeTestBoardInfo) {
        self.mode = mode
        self.peripheral = peripheral
        self.boardInfo = boardInfo
        
        super.init()
        
        self.peripheral.delegate = self
        self.registerForPeripheralValuesUpdates()
    }
    
    func getAllAvailableSettings() -> [SILRangeTestSetting] {
        return Array(model.keys)
    }
    
    func getValue(forSetting setting: SILRangeTestSetting) -> Double {
        let model = self.model[setting]!
        
        return model.selectedValue
    }
    
    func getStringValue(forSetting setting: SILRangeTestSetting) -> String {
        let model = self.model[setting]!
        
        if let valueIdx = model.availableValues.firstIndex(of: model.selectedValue) {
            return model.availableStringValues[valueIdx]
        } else {
            return model.availableStringValues[0]
        }
    }
    
    private func set(value: Double?, andAvailableValues availableValues: [Double]?, andAvailableStringValues availableStringValues: [String]?, forSetting setting: SILRangeTestSetting) {
        let model = self.model[setting]!
        
        model.update(withSelectedValue: value ?? model.defaultValue, andAvailableValues: availableValues ?? model.availableValues, andAvailableStringValues: availableStringValues ?? model.availableStringValues)
        
        delegate?.updated(setting: setting)
        
        if value != nil && availableValues != nil {
            receivedPeripheralValues |= setting.rawValue
        }
    }
    
    private func set(value: Double?, andAvailableValues availableValues: [Double]?, forSetting setting: SILRangeTestSetting) {
        let model = self.model[setting]!
        
        model.update(withSelectedValue: value ?? model.defaultValue, andAvailableValues: availableValues ?? model.availableValues)
        
        delegate?.updated(setting: setting)
        
        if value != nil && availableValues != nil {
            receivedPeripheralValues |= setting.rawValue
        }
    }
    
    func set(value: Double?, forSetting setting: SILRangeTestSetting) {
        let model = self.model[setting]!
        
        model.update(withSelectedValue: value ?? model.defaultValue)
        
        delegate?.updated(setting: setting)
        
        if value != nil {
            receivedPeripheralValues |= setting.rawValue
        }
    }
    
    func getTitle(forSetting setting: SILRangeTestSetting) -> String {
        let model = self.model[setting]!
        
        return model.title
    }
    
    func getAvailableValues(forSetting setting: SILRangeTestSetting) -> [Double] {
        let model = self.model[setting]!
        
        return model.availableValues
    }
    
    func getAvailableStringValues(forSetting setting: SILRangeTestSetting) -> [String] {
        let model = self.model[setting]!
        
        return model.availableStringValues
    }
    
    func updatePeripheral(forSetting setting: SILRangeTestSetting) {
        let model = self.model[setting]!
        let value = model.selectedValue
        
        switch setting {
        case .txPower:
            peripheral.setTxPower(value)
            break
        case .payloadLength:
            peripheral.setPayloadLength(value)
            break
        case .maWindowSize:
            peripheral.setMaWindowSize(value)
            break
        case .channelNumber:
            peripheral.setChannel(value)
            break
        case .packetCount:
            peripheral.setPacketCount(value)
            break
        case .remoteId:
            peripheral.setRemoteId(value)
            break
        case .selfId:
            peripheral.setSelfId(value)
            break
        case .phyConfig:
            peripheral.setPhyConfig(value)
            break
        case .all:
            break
        }
    }
    
    func didUpdate(connectionState: CBPeripheralState) {
        if connectionState == .connected {
            self.registerForPeripheralValuesUpdates()
        }
    }
    
    func didUpdate(manufacturerData: SILRangeTestManufacturerData?) {
        guard let manufData = manufacturerData else {
            handleMissingManufacturerData()
            return
        }
        
        if let totalRx = manufData.packetsCounter, let rx = manufData.packetsReceived {
            let rxValue = Int(rx)
            let totalRxValue = Int(totalRx)
            let perValue = totalRxValue == 0 ? 0 : (Float(totalRxValue - rxValue) / Float(totalRxValue)) * 100
            
            maCalculator!.add(rx: rxValue, andTotalRx: totalRxValue)
            delegate?.updated(rx: rxValue, totalRx: totalRxValue, per: perValue, ma: maCalculator!.value)
        }
        
        if let rssi = manufData.rssi {
            delegate?.updated(rssi: Int(rssi))
        }
        
    }
    
    private func handleMissingManufacturerData() {
        isTestStarted = false
        peripheral.connect()
        registerForPeripheralValuesUpdates()
    }
    
    private func startTest() {
        if (self.mode == .RX) {
            let maWindowSize = self.model[.maWindowSize]!.selectedValue
            maCalculator = SILRangeTestMovingAverageCalculator(withWindowSize: Int(maWindowSize))
            peripheral.startGetheringAdvertisementData()
        } else if (self.mode == .TX) {
            let expectedNumberOfPacketsPerSecond: TimeInterval = 14
            let updateInterval: TimeInterval = 1/expectedNumberOfPacketsPerSecond
            let callback: (Int) -> Void = { [weak self] (value) in
                DispatchQueue.main.async {
                    self?.delegate?.updated(totalTx: value)
                }
            }
            
            let packetCount = isPacketRepeatEnabled ? -1 : Int(model[.packetCount]!.selectedValue)
            
            txValueUpdater = SILRangeTestTXValueUpdater(withValue: 0, upToValue: packetCount, updateInterval: updateInterval, callback: callback)
        }
    }
    
    private func stopTest() {
        if (self.mode == .RX) {
            peripheral.stopGetheringAdvertisementData()
        } else if (self.mode == .TX) {
            self.txValueUpdater = nil
        }
    }
}

//MARK: - Periperal Values
extension SILRangeTestAppViewModel {
    private func registerForPeripheralValuesUpdates() {
        guard peripheral.state == .connected else {
            return
        }
        
        receivedPeripheralValues = 0
        
        peripheral.radioMode(callback: onReceive(radioMode:))
        peripheral.phyConfigList(callback: onReceive(phyConfigList:))
        peripheral.phyConfig(callback: onReceive(phyConfig:))
        peripheral.txPower(callback: onReceive(txPower:minValue:maxValue:))
        peripheral.payloadLength(callback: onReceive(payloadLength:minValue:maxValue:))
        peripheral.maWindowSize(callback: onReceive(maWindowSize:minValue:maxValue:))
        peripheral.channel(callback: onReceive(channel:minValue:maxValue:))
        peripheral.packetsSent(callback: onReceive(packetsSent:))
        peripheral.packetCount(callback: onReceive(packetCount:minValue:maxValue:))
        peripheral.remoteId(callback: onReceive(remoteId:minValue:maxValue:))
        peripheral.selfId(callback: onReceive(selfId:minValue:maxValue:))
        peripheral.isUartLogEnabled(callback: onReceive(isUartLogEnabled:))
        peripheral.isRunning(callback: onReceive(isRunning:))
        
        peripheral.packetsCnt(callback: onReceive(totalRx:))
        peripheral.packetsReceived(callback: onReceive(rx:))
        peripheral.per(callback: onReceive(per:))
        peripheral.ma(callback: onReceive(ma:))
    }
    
    private func onReceive(radioMode: Int?) {
        guard let mode = radioMode else { return }

        if self.mode.rawValue != mode {
            self.peripheral.setRadioMode(self.mode.rawValue)
        }
    }
    
    private func onReceive(phyConfigList: [Int : String]?) {
        let value = self.getValue(forSetting: .phyConfig)
        let phyConfigIds = phyConfigList?.keys.sorted()
        let availableValues = phyConfigIds?.map { Double($0) }
        let availableStringValues = phyConfigIds?.map { phyConfigList![$0]! }
        
        self.set(value: value, andAvailableValues: availableValues, andAvailableStringValues: availableStringValues, forSetting: .phyConfig)
    }
    
    private func onReceive(phyConfig: Double?) {
        self.set(value: phyConfig, forSetting: .phyConfig)
    }
    
    private func onReceive(txPower: Double?, minValue: Double?, maxValue: Double?) {
        var availableValues: [Double]? = nil

        if let minVal = minValue, let maxVal = maxValue {
            availableValues = Array(stride(from: minVal, through: maxVal, by: 0.5))
        }
        
        self.set(value: txPower, andAvailableValues: availableValues, forSetting: .txPower)
    }
    
    private func onReceive(payloadLength: Double?, minValue: Double?, maxValue: Double?) {
        var availableValues: [Double]? = nil
        
        if let minVal = minValue, let maxVal = maxValue {
            availableValues = Array(stride(from: minVal, through: maxVal, by: 1))
        }
        
        self.set(value: payloadLength, andAvailableValues: availableValues, forSetting: .payloadLength)
    }
    
    private func onReceive(maWindowSize: Double?, minValue: Double?, maxValue: Double?) {
        var availableValues: [Double]? = nil
        
        if let minVal = minValue, let maxVal = maxValue {
            let minValPower = Int(log2(minVal))
            let maxValPower = Int(log2(maxVal))
            availableValues = []
            
            for power in minValPower...maxValPower {
                availableValues?.append(pow(2, Double(power)))
            }
        }
        
        self.set(value: maWindowSize, andAvailableValues: availableValues, forSetting: .maWindowSize)
    }
    
    private func onReceive(channel: Double?, minValue: Double?, maxValue: Double?) {
        var availableValues: [Double]? = nil
        
        if let minVal = minValue, let maxVal = maxValue {
            availableValues = Array(stride(from: minVal, through: maxVal, by: 1))
        }
        
        self.set(value: channel, andAvailableValues: availableValues, forSetting: .channelNumber)
    }
    
    private func onReceive(packetsSent: Int?) {
        let txValue = packetsSent ?? 0
        
        if let txValueUpdaterObj = txValueUpdater, isTestStarted {
            txValueUpdaterObj.update(withActualValue: txValue)
        } else {
            self.delegate?.updated(totalTx: txValue)
        }
    }
    
    private func onReceive(packetCount: Double?, minValue: Double?, maxValue: Double?) {
        if let newValue = packetCount, newValue == Double(UInt16.max) {
            self.isPacketRepeatEnabled = true
            
            if packetCount != nil && minValue != nil && maxValue != nil {
                receivedPeripheralValues |= SILRangeTestSetting.packetCount.rawValue
            }
        } else {
            self.set(value: packetCount, forSetting: .packetCount)
            self.isPacketRepeatEnabled = false
        }
    }
    
    private func onReceive(remoteId: Double?, minValue: Double?, maxValue: Double?) {
        var availableValues: [Double]? = nil
        
        if let minVal = minValue, let maxVal = maxValue {
            availableValues = Array(stride(from: minVal, through: maxVal, by: 1))
        }
        
        self.set(value: remoteId, andAvailableValues: availableValues, forSetting: .remoteId)
    }
    
    private func onReceive(selfId: Double?, minValue: Double?, maxValue: Double?) {
        var availableValues: [Double]? = nil
        
        if let minVal = minValue, let maxVal = maxValue {
            availableValues = Array(stride(from: minVal, through: maxVal, by: 1))
        }
        
        self.set(value: selfId, andAvailableValues: availableValues, forSetting: .selfId)
    }
    
    private func onReceive(isUartLogEnabled: Bool?) {
        self.isUartLogEnabled = isUartLogEnabled ?? false
    }
    
    private func onReceive(isRunning: Bool?) {
        self.isTestStarted = isRunning ?? false
    }
    
    private func onReceive(rx: Int?) {
        guard let rxValue = rx, rxValue != 0, rxValue != Int(UInt16.max) else {
            return
        }
        
        delegate?.updated(rx: rxValue)
    }
    
    private func onReceive(totalRx: Int?) {
        guard let totalRxValue = totalRx, totalRxValue != 0, totalRxValue != Int(UInt16.max) else {
            return
        }
        
        delegate?.updated(totalRx: totalRxValue)
    }
    
    private func onReceive(ma: Double?) {
        guard let maValue = ma, maValue != 0 else {
            return
        }
        
        delegate?.updated(ma: Float(maValue))
    }
    
    private func onReceive(per: Double?) {
        guard let perValue = per, perValue != 0 else {
            return
        }
        
        delegate?.updated(per: Float(perValue))
    }
}
