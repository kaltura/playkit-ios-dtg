//
//  CCBridge.m
//  Pods
//
//  Created by Noam Tamim on 10/07/2017.
//
//

#import "CCBridge.h"
#import <CommonCrypto/CommonCrypto.h>

@implementation CCBridge
    +(NSString*)md5WithString:(NSString*)str {
        NSData* data = [str dataUsingEncoding:NSUTF8StringEncoding];
        unsigned char digest[CC_MD5_DIGEST_LENGTH];
        CC_MD5(data.bytes, (CC_LONG)data.length, digest);
        
        NSMutableString* hex = [[NSMutableString alloc] init];
        for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
            [hex appendFormat:@"%02x", digest[i]];
        }
        return hex;
    }

@end
