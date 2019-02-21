//
//  ObjCUtils.h
//  DownloadToGo
//
//  Created by Noam Tamim on 20/02/2019.
//

#import <Foundation/Foundation.h>

@interface NSString (m3u8)
- (NSDictionary<NSString*,NSString*> * _Nonnull)parseM3U8AttributesAfter:(NSString*)prefix;
@end

