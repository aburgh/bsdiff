//
//  main.m
//  bsreplace
//
//  Created on 1/27/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <err.h>
#include <libgen.h>

@interface NSObject (NSObjectAdditions)
- (__strong const char *)UTF8Description;
@end

@implementation NSObject (NSObjectAdditions)

- (__strong const char *)UTF8Description {
	return [[self description] UTF8String];
}
@end

// Prototypes

/* The hex string format requires each byte have both nibbles and
   there be one space between each byte. I.e.: "01 02 03 FF FA EE"
 */
NSData * HexToData(NSString *hex);

// Declarations
NSData * HexToData(NSString *hex) {
	
	NSUInteger byteCount = [[hex stringByReplacingOccurrencesOfString:@" " withString:@""] length] / 2;
	
	NSScanner *scanner = [NSScanner scannerWithString:hex];
	
	NSMutableData *data = [NSMutableData dataWithLength:byteCount];
	
	uint32_t byte;
	uint8_t *bytes = [data mutableBytes];
	
	for (int i = 0; [scanner isAtEnd] == NO; i++) {
		if ([scanner scanHexInt:&byte])
			bytes[i] = (byte & 0xff);
		else
			return nil; // Abort
	}
	return data;
}

int main (int argc, char * argv[])
{
	NSError *error;

	@autoreleasepool {

	    NSArray *args = [[NSProcessInfo processInfo] arguments];
		
		if (argc < 5 || !(argc & 1))
			errx(EXIT_FAILURE, "usage: %s infile outfile search_bytes replace_bytes [search_bytes replace_bytes ...]\n", basename(argv[0]));
		
		NSString *inFile =  [args objectAtIndex:1];
		NSString *outFile = [args objectAtIndex:2]; 
		
		NSMutableData *contents = [NSMutableData dataWithContentsOfFile:inFile options:0 error:&error];
		if (!contents)
			err(EXIT_FAILURE, "open %s", argv[1]);
			
	    for (int i = 3; i < argc; i += 2) {
		
			NSData *oldBytes = HexToData([args objectAtIndex:i]);
			if (!oldBytes)
				errx(EXIT_FAILURE, "failed to convert hex string '%s'", argv[i]);
			
			NSData *newBytes = HexToData( [args objectAtIndex: i + 1 ] );
			if (!oldBytes)
				errx(EXIT_FAILURE, "failed to convert hex string '%s'", argv[i+1]);
			
			// The intended purpose of this utility is to patch files with changes that don't change the file size.
//			NSCAssert2([oldBytes length] == [newBytes length], @"byte array %@ differs in length from %@", oldBytes, newBytes );
			if ([oldBytes length] != [newBytes length]) {
				warnx("length of byte array %s differs from %s, skipping...", [oldBytes UTF8Description], [newBytes UTF8Description]);
				continue;
			}
			
			// Count occurrences
			NSRange found, search;
			search = NSMakeRange(0, [contents length]);
			NSUInteger count;
			for (count = 0; search.location < [contents length]; count++) {

				found = [contents rangeOfData:oldBytes options:0 range:search];
				if (found.location == NSNotFound)
					break;
				
				search = NSMakeRange(found.location + 1, [contents length] - found.location - 1);
			}
			if (count != 1) {
				fprintf(stderr, "Found %ld occurrences, skipping sequence %s\n", count, [oldBytes UTF8Description]);
				continue;
			}
			
			// Do replacement
			NSRange range = [contents rangeOfData:oldBytes options:0 range:NSMakeRange(0, [contents length])];
			[contents replaceBytesInRange:range withBytes:[newBytes bytes]];
		}
		
		if ([contents writeToFile:outFile options:NSDataWritingAtomic error:&error] == NO)
			errx(EXIT_FAILURE, "error writing %s: %s", argv[2], [[error localizedDescription] UTF8String]);
		
	}
    return EXIT_SUCCESS;
}

