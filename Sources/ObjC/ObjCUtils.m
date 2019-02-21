//
//  ObjCUtils.m
//  DownloadToGo
//
//  Created by Noam Tamim on 20/02/2019.
//

#import "ObjCUtils.h"

@implementation NSString (m3u8)

- (NSMutableDictionary<NSString*,NSString*> * _Nonnull)parseM3U8AttributesAfter:(NSString*)prefix {
    
    NSRange range = [self rangeOfString:prefix];
    NSString *attribute_list = [self substringFromIndex:range.location + range.length];
    
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


@end
