//
//  ObjCUtils.m
//  DownloadToGo
//
//  Created by Noam Tamim on 20/02/2019.
//

#import "ObjCUtils.h"
#import <CommonCrypto/CommonCrypto.h>

NSDictionary<NSString*,NSString*> * parseM3U8Attributes(NSString* str, NSString* prefix) {
    
    if (![str hasPrefix:prefix]) {
        return nil;
    }
    NSString *attribute_list = [str substringFromIndex:prefix.length];
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    NSRange equalMarkRange = [attribute_list rangeOfString:@"="];
    
    while (NSNotFound != equalMarkRange.location) {
        NSString *key = [attribute_list substringToIndex:equalMarkRange.location];
        attribute_list = [attribute_list substringFromIndex:equalMarkRange.location +1];
        NSString *value = @"";
        
        if ([attribute_list hasPrefix:@"\""]) {
            attribute_list = [attribute_list substringFromIndex:1];
            NSRange quoteRange = [attribute_list rangeOfString:@"\""];
            value = [attribute_list substringToIndex:quoteRange.location];
            attribute_list = [attribute_list substringFromIndex:quoteRange.location +1];
        } else {
            NSRange commaRange = [attribute_list rangeOfString:@","];
            if (NSNotFound == commaRange.location) {
                value = attribute_list;
            } else {
                value = [attribute_list substringToIndex:commaRange.location];
                attribute_list = [attribute_list substringFromIndex:commaRange.location +1];
            }
        }
        if ([attribute_list hasPrefix:@","]) {
            attribute_list = [attribute_list substringFromIndex:1];
        }
        equalMarkRange = [attribute_list rangeOfString:@"="];
        
        dict[key] = value;
    }
    return dict;
}

NSString* md5WithString(NSString* str) {
    NSData* data = [str dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, digest);
    
    NSMutableString* hex = [[NSMutableString alloc] init];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}
