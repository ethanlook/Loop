//
//  TidepoolService.swift
//  Loop
//
//  Created by Ethan Look on 8/16/16.
//  Copyright © 2016 Ethan Look,
//    based on original by Nathan Racklyeft, Pete Schwamb. All rights reserved.
//

import Foundation
import TidepoolKit
import MinimedKit

// Encapsulates a Tidepool site and its authentication
struct TidepoolService: ServiceAuthentication {
    var credentials: [ServiceCredential]
    
    let title: String = NSLocalizedString("Tidepool", comment: "The title of the Tidepool service")
    
    init(username: String?, password: String?) {
        credentials = [
            ServiceCredential(
                title: NSLocalizedString("User email", comment: "The title of the Tidepool user email credential"),
                placeholder: NSLocalizedString("example@domain.com", comment: "The placeholder text for the Tidepool user email credential"),
                isSecret: false,
                keyboardType: .EmailAddress,
                value: username
            ),
            ServiceCredential(
                title: NSLocalizedString("Password", comment: "The title of the Tidepool password credential"),
                placeholder: nil,
                isSecret: true,
                keyboardType: .ASCIICapable,
                value: password
            )
        ]
        
        verify { _, _ in }
    }
    
    // The api client instance, if credentials are present
    private(set) var apiClient: TidepoolApiClient? {
        didSet {
            //            apiClient?.errorHandler = { (error: ErrorType, context: String) -> Void in
            //                print("Error \(error), while \(context)")
            //            }
        }
    }
    
    var username: String? {
        return credentials[0].value
    }
    
    var password: String? {
        return credentials[1].value
    }
    
    private(set) var isAuthorized: Bool = false
    
    mutating func verify(completion: (success: Bool, error: ErrorType?) -> Void) {
        guard let username = username, password = password else {
            completion(success: false, error: nil)
            return
        }
        
        let apiClient: TidepoolApiClient = TidepoolApiClient()
        apiClient.login(username, password: password) { (success, error) in
            completion(success: success, error: error)
        }
        self.apiClient = apiClient
    }
    
    mutating func reset() {
        credentials[0].value = nil
        credentials[1].value = nil
        isAuthorized = false
        apiClient = nil
    }
    
    static func translatePumpEvents(events: [TimestampedHistoryEvent]) -> TDSet {
        
        let results = TDSet()
        
        var lastWizard: BolusWizardEstimatePumpEvent?
        var lastBasal: TempBasalPumpEvent?
        
        for event in events {
            
            switch event.pumpEvent {
                
            case let bgReceived as BGReceivedPumpEvent:
                
                results.add(TDSmbg(units: .MGDL, value: Double(bgReceived.amount), time: event.date))
                
            case let bolusNormal as BolusNormalPumpEvent:
                
                var bolusOrWizard: TidepoolData
                
                let bolus: TDBolus = TDBolus(normal: bolusNormal.amount,
                                             expectedNormal: bolusNormal.programmed,
                                             time: Datetime.dateFromComponents(bolusNormal.timestamp))
                bolusNormal.timestamp
                
                if let wizard = lastWizard where wizard.timestamp == bolusNormal.timestamp {
                    bolusOrWizard = TDWizard(units: .MGDL,
                                             bolus: bolus,
                                             bgInput: Double(wizard.bloodGlucose),
                                             bgTarget: TDWizard.BGTarget(low: Double(wizard.bgTargetLow), high: Double(wizard.bgTargetHigh)),
                                             carbInput: wizard.carbohydrates,
                                             insulinCarbRatio: Int(wizard.carbRatio),
                                             insulinOnBoard: wizard.unabsorbedInsulinTotal, // Is this correct??
                        insulinSensitivity: Double(wizard.insulinSensitivity),
                        recommended: TDWizard.RecommendedBolus(carb: wizard.foodEstimate,
                            correction: wizard.correctionEstimate,
                            net: wizard.bolusEstimate),
                        time: Datetime.dateFromComponents(wizard.timestamp))
                } else {
                    bolusOrWizard = bolus
                }
                
                results.add(bolusOrWizard)
                
            case let bolusWizard as BolusWizardEstimatePumpEvent:
                
                lastWizard = bolusWizard
                
            case let tempBasal as TempBasalPumpEvent:
                
                lastBasal = tempBasal
                
            case let tempBasalDuration as TempBasalDurationPumpEvent:
                
                if let tempBasal = lastBasal {
                    results.add(TDBasal(deliveryType: .Temp,
                        duration: tempBasalDuration.duration,
                        rate: tempBasal.rate,
                        time: Datetime.dateFromComponents(tempBasal.timestamp)))
                }
                
            default:
                break
            }
        }
        
        return results
    }
}