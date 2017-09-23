//
//  AppLaunch.swift
//  AppLaunch
//
//  Created by Chethan Kumar on 9/23/17.
//  Copyright © 2017 IBM. All rights reserved.
//

import Foundation
import BMSCore
import SwiftyJSON

// ─────────────────────────────────────────────────────────────────────────

public class AppLaunch:NSObject{
    
public private(set) var clientSecret: String?

public private(set) var applicationId: String?

public private(set) var region: String?

private var deviceId = String()

public static let sharedInstance = AppLaunch()

private var bmsClient = BMSClient.sharedInstance

private var isInitialized = false

private var isUserRegistered = false

private var userId:String = String()
    
private var features:JSON = nil
    
//
// ─── INITIALIZE ────────────────────────────────────────────────────────────
//
    
public func initializeWithAppGUID (applicationId: String, clientSecret: String, region: String) {
    
    if AppLaunchUtils.validateString(object: clientSecret) &&  AppLaunchUtils.validateString(object: applicationId){
        
        self.clientSecret = clientSecret
        self.applicationId = applicationId
        self.region = region
        isInitialized = true;
        
        let authManager  = BMSClient.sharedInstance.authorizationManager
        self.deviceId = authManager.deviceIdentity.ID!
        AppLaunchUtils.saveValueToNSUserDefaults(value: self.deviceId, key: DEVICE_ID)
    }
    else{
        print(MSG__CLIENT_OR_APPID_NOT_VALID)
    }
}
    
//
// ─── REGISTER USER ──────────────────────────────────────────────────────────
//

public func registerWith(userId:String,completionHandler:@escaping(_ response:String, _ statusCode:Int, _ error:String) -> Void){
    if(isInitialized) {
        
        if(AppLaunchUtils.getValueToNSUserDefaults(key: IS_USER_REGISTERED) == TRUE){
            completionHandler(MSG__USER_ALREADY_REGISTERED,201,"")
        } else {
        
            var deviceData:JSON = JSON()
            deviceData[DEVICE_ID].string = self.deviceId
            deviceData[MODEL].string = UIDevice.current.modelName
            deviceData[BRAND].string = APPLE
            deviceData[OS_VERSION].string = UIDevice.current.systemVersion
            deviceData[PLATFORM].string = IOS
            deviceData[APP_ID].string = Bundle.main.bundleIdentifier!
            deviceData[APP_VERSION].string = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            deviceData[APP_NAME].string = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
            deviceData[USER_ID].string = userId
            
            let userRegUrl = REGISTRATION_SERVER+"/apps/\(self.applicationId!)/users"
            
            var  headers = [String:String]()
            headers.updateValue(APPLICATION_JSON, forKey: CONTENT_TYPE)
            headers.updateValue(self.clientSecret!, forKey: CLIENT_SECRET)
            
            let createUserRequest = Request(url: userRegUrl, method: HttpMethod.POST,headers: headers, queryParameters: nil, timeout: 60)
            
            createUserRequest.send(requestBody: deviceData.description.data(using: .utf8),completionHandler:{(response,error) in
                
                if(response != nil){
                    let responseText = response?.responseText ?? ""
                    let status = response?.statusCode ?? 0
                    if(status == 400){
                        completionHandler("", status, responseText)
                        self.isUserRegistered = false
                    }else{
                        self.isUserRegistered = true
                        self.userId = userId
                        AppLaunchUtils.saveValueToNSUserDefaults(value: TRUE, key: IS_USER_REGISTERED)
                        completionHandler(responseText,status,"")
                    }
                }else if let responseError = error{
                    completionHandler("", 500, responseError.localizedDescription)
                }
            })
        }
    }
}
    
//
// ─── UPDATE USER ───────────────────────────────────────────────────────────
//

public func updateUserWith(userId:String,attribute:String,value:Any, completionHandler:@escaping(_ response:String, _ statusCode:Int, _ error:String) -> Void){
    
    var deviceData:JSON = JSON()
    deviceData[DEVICE_ID].string = self.deviceId
    deviceData[USER_ID].string = self.userId
    switch type(of: value) {
    case is String.Type:
        deviceData[attribute].string = value as! String
        
    case is Numeric.Type:
        deviceData[attribute].number = value as! NSNumber
        
    case is Bool.Type:
        deviceData[attribute].boolValue = value as! Bool
        
    default:
        break
    }
    
    
    let userRegUrl = REGISTRATION_SERVER+"/apps/\(self.applicationId!)/users/\(userId)"
    
    var  headers = [String:String]()
    headers.updateValue(APPLICATION_JSON, forKey: CONTENT_TYPE)
    headers.updateValue(self.clientSecret!, forKey: CLIENT_SECRET)
    
    let createUserRequest = Request(url: userRegUrl, method: HttpMethod.PUT,headers: headers, queryParameters: nil, timeout: 60)
    
    createUserRequest.send(requestBody: deviceData.description.data(using: .utf8),completionHandler:{(response,error) in
        
        if(response != nil){
            let responseText = response?.responseText ?? ""
            let status = response?.statusCode ?? 0
            if(status == 400){
                completionHandler("", status, responseText)
                self.isUserRegistered = false
            }else{
                self.isUserRegistered = true
                self.userId = userId
                completionHandler(responseText,status,"")
                
            }
        }else if let responseError = error{
            completionHandler("", 500, responseError.localizedDescription)
        }
    })
}
    
//
// ─── ACTIONS ───────────────────────────────────────────────────────────────
//
    
public func actions(completionHandler:@escaping(_ features:JSON?, _ statusCode:Int?, _ error:String) -> Void){
    
    if(isInitialized && (AppLaunchUtils.getValueToNSUserDefaults(key: IS_USER_REGISTERED) == TRUE)){
        
        
        //TODO build url for different bluemix zones and envs
        let resourceURL:String = CLIENT_ACTIVITY_SERVER+"/apps/\(self.applicationId!)/users/\(self.userId)/devices/\(self.deviceId)/actions"
        
        //TODO add client secret in headers
        var headers = [CONTENT_TYPE : APPLICATION_JSON]
        headers.updateValue(self.clientSecret!, forKey: CLIENT_SECRET)
        
        let getActionsRequest = Request(url: resourceURL, method: HttpMethod.GET,headers: headers, queryParameters: nil, timeout: 60)
        
        
        getActionsRequest.send(completionHandler: { (response, error) in
            if response?.statusCode != nil {
                let status = response?.statusCode ?? 0
                let responseText = response?.responseText ?? ""
                
                if(status == 404){
                    print("[404] Actions Not found")
                    completionHandler(nil,status,responseText)
                }else{
                    if let data = responseText.data(using: String.Encoding.utf8) {
                        let respJson = JSON(data: data)
                        
                        print("response data from server \(responseText)")
                        self.features = respJson["features"];
                        completionHandler(respJson["features"],200,"")
                    }
                }
                
            }else {
                completionHandler([], 500 , MSG__ERR_GET_ACTIONS)
            }
        })
        
    }else{
        completionHandler([], 500 , MSG__ERR_NOT_REG_NOT_INIT)
        
    }
}
    
//
// ─── FEATURES ──────────────────────────────────────────────────────────────
//

public func hasFeatureWith(code:String) -> Bool{
    var hasFeature = false
    for(key,feature) in self.features{
        if let featureCode = feature["code"].string{
            if featureCode == code{
                hasFeature = true
            }
        }
    }
    return hasFeature
}
    
public func getValueFor(featureWithCode:String,variableWithCode:String) -> String{
    for(key,feature) in self.features{
        if let featureCode = feature["code"].string{
            if featureCode == featureWithCode{
                for(k,variable) in feature["variables"]{
                    if let varibleCode = variable["code"].string{
                        if varibleCode == variableWithCode{
                            return variable["value"].stringValue
                        }
                    }
                }
            }
        }
    }
    return ""
}

//
// ─── METRICS ──────────────────────────────────────────────────────────────
//

public func sendMetricsWith(code:String) -> Void{
    if(isInitialized && isUserRegistered){
        
        var metricsData:JSON = JSON()
        metricsData[DEVICE_ID].string = self.deviceId
        metricsData[USER_ID].string = self.userId
        metricsData[METRIC_CODES].arrayObject = [code]
        
        print("metrics payload \(metricsData.description)")
        
        let resourceURL:String = CLIENT_ACTIVITY_SERVER+"/apps/\(self.applicationId!)/users/\(self.userId)/devices/\(self.deviceId)/events/metrics"
        
        //TODO add client secret in headers
        var headers = [CONTENT_TYPE : APPLICATION_JSON]
        headers.updateValue(self.clientSecret!, forKey: CLIENT_SECRET)
        
        let metricsRequest = Request(url: resourceURL, method: HttpMethod.POST,headers: headers, queryParameters: nil, timeout: 60)
        
        metricsRequest.send(requestBody: metricsData.description.data(using: .utf8),completionHandler:{(response,error) in
            
            let status = response?.statusCode ?? 0
            if(status == 200){
                print("sent metrics for code : \(code)")
            }else if let responseError = error{
                print("Error in sending metrics for code : \(code) with error :\(responseError.localizedDescription)")
            }
            
        })
    }else{
        print(MSG__ERR_METRICS_NOT_INIT)
    }
    
}
    

}
