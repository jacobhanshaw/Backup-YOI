//
//  SimpleFacebookShare.m
//  simple-share
//
//  Created by  on 30.05.12.
//  Copyright 2012 Felix Schulze. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import <FacebookSDK/FacebookSDK.h>
#import "SimpleFacebookShare.h"
#import "AppServices.h"
#import "SVProgressHUD.h"

@interface SimpleFacebookShare()
{
    NSString *appActionLink;
}

@property(nonatomic, readwrite) int noteId;

@end

@implementation SimpleFacebookShare 

@synthesize noteId;

- (id)initWithAppName:(NSString *)theAppName appUrl:(NSString *)theAppUrl {
    self = [super init];
    if (self) {
        NSArray *actionLinks = [NSArray arrayWithObjects:[NSDictionary dictionaryWithObjectsAndKeys:theAppName, @"name", theAppUrl, @"link", nil], nil];
        NSError *error = nil;

        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:actionLinks options:NSJSONWritingPrettyPrinted error:&error];
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        appActionLink = jsonString;
    }
    return self;
}

- (BOOL)handleOpenURL:(NSURL *)theUrl {
    return [FBSession.activeSession handleOpenURL:theUrl];
}


- (void)logOut {
    [FBSession.activeSession closeAndClearTokenInformation];

    //Delete data from User Defaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"FBAccessTokenInformationKey"];

    //Remove facebook Cookies:
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [storage cookies]) {
        if ([cookie.domain isEqualToString:@".facebook.com"] || [cookie.domain isEqualToString:@"facebook.com"]) {
            [storage deleteCookie:cookie];
            NSLog(@"Delete facebook cookie: %@", cookie);
        }
    }
    [defaults synchronize];
}

- (void)shareUrl:(NSURL *)theUrl {
    [self _shareInitalParams:@{
            @"link" : [theUrl absoluteString],
            @"actions" : appActionLink
    }];
}

- (void)shareText:(NSString *)theText {
    [self _shareInitalParams:@{
     @"description" : theText,
     @"actions" : appActionLink
     }];
}

//NEW METHOD
- (void)shareText:(NSString *) text withImage:(NSString *)imageURL title:(NSString *) title andURL:(NSString *) urlString fromNote:(int)aNoteId
{
    self.noteId = aNoteId;
    [self _shareInitalParams:@{
     @"picture"     : imageURL,
     @"name"        : title,
     @"description" : text,
     @"message"     : text,
     @"link"        : urlString
    }];
}

- (void)_shareInitalParams:(NSDictionary *)params {
    if (FBSession.activeSession.isOpen) {
        [self _shareAndReauthorize:params];
    }
    else {
        [self _shareAndOpenSession:params];
    }
}

- (void)_shareAndReauthorize:(NSDictionary *)params {
    if ([FBSession.activeSession.permissions indexOfObject:@"publish_actions"] == NSNotFound) {
        [FBSession.activeSession requestNewPublishPermissions:[NSArray arrayWithObject:@"publish_actions"]
                                              defaultAudience:FBSessionDefaultAudienceFriends
                                            completionHandler:^(FBSession *session, NSError *error) {
                                                if (!error) {
                                                    NSLog(@"Authorization Error: %@", error);
                                                    [SVProgressHUD showErrorWithStatus:@"Authorization Error"];
                                                }
                                                else {
                                                    [self _shareParams:params];

                                                }
                                            }];
    }
    else {
        [self _shareParams:params];
    }
}

- (void)_shareAndOpenSession:(NSDictionary *)params {

    if (FBSession.activeSession.state == FBSessionStateCreatedTokenLoaded) {
        [FBSession.activeSession openWithCompletionHandler:^(FBSession *session, FBSessionState status, NSError *error) {
            [self _shareAndReauthorize:params];
        }];
    }
    else {
        [FBSession openActiveSessionWithPublishPermissions:@[@"publish_actions"] defaultAudience:FBSessionDefaultAudienceFriends allowLoginUI:YES completionHandler:^(FBSession *session, FBSessionState status, NSError *error) {
            if (error) {
                NSLog(@"Authorization Error: %@", error);
                [SVProgressHUD showErrorWithStatus:@"Authorization Error."];
            }
            else {
                [self _shareAndReauthorize:params];
            }
        }];
    }
}
//MODIFIED METHOD
- (void)_shareParams:(NSDictionary *)params {
    __weak SimpleFacebookShare *selfForBlock = self;
    [FBWebDialogs presentFeedDialogModallyWithSession:nil parameters:params handler:^(FBWebDialogResult result, NSURL *resultURL, NSError *error) {
        if (error) {
            NSLog(@"Saving Error: %@", error);
            [SVProgressHUD showErrorWithStatus:@"Saving Error."];
        } else {
            NSDictionary *resultParams = [selfForBlock _parseURLParams:[resultURL query]];
            if ([resultParams valueForKey:@"error_code"])
            {
                [SVProgressHUD showErrorWithStatus:@"An Error Has Occured."];
                NSLog(@"Error: %@", [resultParams valueForKey:@"error_msg"]);
            }
            else if ([resultParams valueForKey:@"post_id"])
            {
                [SVProgressHUD showSuccessWithStatus:@"Success"];
                [[AppServices sharedAppServices] sharedNoteToFacebook: selfForBlock.noteId];
            }
        }
    }];
}

- (void)getUsernameWithCompletionHandler:(void (^)(NSString *username, NSError *error))completionHandler {
    if (completionHandler) {
        if (FBSession.activeSession.state == FBSessionStateCreatedTokenLoaded) {
            __weak SimpleFacebookShare *selfForBlock = self;
            [FBSession.activeSession openWithCompletionHandler:^(FBSession *session, FBSessionState status, NSError *error) {
                [selfForBlock _getUserNameWithCompletionHandlerOnActiveSession:completionHandler];

            }];
        }
        [self _getUserNameWithCompletionHandlerOnActiveSession:completionHandler];
    }
}

- (void)_getUserNameWithCompletionHandlerOnActiveSession:(void (^)(NSString *username, NSError *error))completionHandler {
    [FBRequestConnection startWithGraphPath:@"me"
                                 parameters:nil HTTPMethod:@"GET"
                          completionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
                              if (error) {
                                  completionHandler(nil, error);
                              }
                              else {
                                  NSString *username = [result objectForKey:@"name"];
                                  completionHandler(username, nil);
                              }
                          }];
}

- (BOOL)isLoggedIn {
    FBSessionState state = FBSession.activeSession.state;
    if (state == FBSessionStateOpen || state == FBSessionStateCreatedTokenLoaded || state == FBSessionStateOpenTokenExtended) {
        return YES;
    }
    else {
        return NO;
    }
}

- (void)close {
    [FBSession.activeSession close];
}

- (void)handleDidBecomeActive {
    [FBSession.activeSession handleDidBecomeActive];
}

- (NSDictionary *) _parseURLParams:(NSString *)query {
    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    for (NSString *pair in pairs) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        NSString *val =
                [[kv objectAtIndex:1]
                        stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

        [params setObject:val forKey:[kv objectAtIndex:0]];
    }
    return params;
}


@end
