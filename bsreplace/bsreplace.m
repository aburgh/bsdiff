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
#include <stdlib.h>

#define AllowResizing    (1 << 0)
#define AllowMultiples   (1 << 1)

#pragma mark - Categories

@interface NSObject (NSObjectAdditions)
@property (readonly) const char * UTF8Description;

- (__strong const char *)UTF8Description;
@end

@implementation NSObject (NSObjectAdditions)

- (__strong const char *)UTF8Description {
	return [[self description] UTF8String];
}
@end

#pragma mark - Prototypes

/* The hex string format requires each byte have both nibbles. Whitespace
   is consumed and does not affect interpretation of low/high nibble.
   I.e.: "1 2 3 FFAF EE" is read as 0x12, 0x3f, 0xfa, 0xfe
 
   Recommended formats are: "01 02 03 FF AF EE" and "010203FFAFEE"
 */
NSData * HexToData(NSString *hex);

BOOL insert_at_offset(NSMutableData *data, NSNumber *offset, NSData *replacementData);

BOOL replace_at_offset(NSMutableData *data, NSNumber *offset, NSData *replacementData);

BOOL find_and_replace(NSMutableData *data, NSData *oldBytes, NSData *newBytes, NSUInteger options);

NSNumber * parse_offset_arg(NSString *arg);

NSData * parse_hex_arg(NSString *arg);

void print_usage(FILE *outfile, const char *progname);

void exit_usage(NSString *progname, int status);

#pragma mark - Declarations

NSData *HexToData(NSString *hexString) {
	
	const char *hexBytes = [hexString UTF8String];
	NSUInteger hexCount  = strlen(hexBytes);
	
	NSMutableData *data = [NSMutableData dataWithLength:hexCount];
	uint8_t *bytes      = [data mutableBytes];

	uint8_t x = 0; // nibble value
	NSUInteger i, j;
	BOOL hiNibble = YES;
	
	for (i = 0, j = 0; i < hexCount; i++) {

		switch (hexBytes[i]) {
			case '0': x = 0; break;
			case '1': x = 1; break;
			case '2': x = 2; break;
			case '3': x = 3; break;
			case '4': x = 4; break;
			case '5': x = 5; break;
			case '6': x = 6; break;
			case '7': x = 7; break;
			case '8': x = 8; break;
			case '9': x = 9; break;
			case 'a':
			case 'A': x = 10; break;
			case 'b':
			case 'B': x = 11; break;
			case 'c':
			case 'C': x = 12; break;
			case 'd':
			case 'D': x = 13; break;
			case 'e':
			case 'E': x = 14; break;
			case 'f':
			case 'F': x = 15; break;
			case ' ':
			case '\t':
			case '\n':
			case '\r':
				// interpret the previous nibble as the low-nibble
				if (!hiNibble)
					bytes[j++] = x;
				hiNibble = YES;
				continue;
			default:
				err(EXIT_FAILURE, "invalid char: %c at offset: %ld", hexBytes[i], i);
				break;
		}
		if (hiNibble) {
			bytes[j] = (x << 4);
			hiNibble = NO;
		}
		else {
			bytes[j] += x;
			hiNibble = YES;
			j++;
		}
	}
	if (!hiNibble) bytes[j++] = x;
	
	[data setLength:j];
	
	return data;
}

BOOL insert_at_offset(NSMutableData *data, NSNumber *offsetNumber, NSData *replacementData) {
	
	NSUInteger offset = [offsetNumber unsignedIntegerValue];
	
	NSRange range = NSMakeRange(offset, 0);

	if (offset > data.length) {
		warnx("offset %lu exceeds data size, skipping %s", offset, replacementData.UTF8Description);
		return NO;
	}
	[data replaceBytesInRange:range withBytes:replacementData.bytes length:replacementData.length];

	return YES;
}

BOOL replace_at_offset(NSMutableData *data, NSNumber *offsetNumber, NSData *replacementData) {
	
	NSUInteger offset = [offsetNumber unsignedIntegerValue];
	
	NSRange range = NSMakeRange(offset, replacementData.length);
		
	if (NSMaxRange(range) > data.length) {
		warnx("new bytes extend beyond data, skipping: data length: %lu, offset: %lu, replacements length: %lu", data.length, offset, replacementData.length);
		return NO;
	}

	[data replaceBytesInRange:range withBytes:replacementData.bytes length:replacementData.length];
	return YES;
}

BOOL find_and_replace(NSMutableData *data, NSData *oldBytes, NSData *newBytes, NSUInteger options) {

	BOOL limitToOne = ( (options & AllowMultiples) == 0);
	
	if ( (options & AllowResizing) == 0 && oldBytes.length != newBytes.length) {
		warnx("length of byte array %s differs from %s, skipping...", oldBytes.UTF8Description, newBytes.UTF8Description);
		return NO;
	}
	
	// Count occurrences
	NSRange found, search;
	NSUInteger count;

	search = NSMakeRange(0, data.length);

	for (count = 0; search.location < data.length; count++) {
		
		found = [data rangeOfData:oldBytes options:0 range:search];
		if (found.location == NSNotFound)
			break;
		
		search = NSMakeRange(NSMaxRange(found), data.length - NSMaxRange(found));
	}
	
	if ( count == 0 || (limitToOne && count != 1) ) {
		warnx("Found %ld occurrences, skipping sequence %s", count, oldBytes.UTF8Description);
		return NO;
	}

	// Do replacement
	search = NSMakeRange(0, data.length);

	while (search.length > newBytes.length) {

		found = [data rangeOfData:oldBytes options:0 range:search];

		if (found.location == NSNotFound) break;

		[data replaceBytesInRange:found withBytes:newBytes.bytes length:newBytes.length];

		search.location = found.location + newBytes.length;
		search.length   = data.length - search.location;
	}

	return YES;
}

NSNumber * parse_offset_arg(NSString *arg) {

	errno = 0;

	long long value = strtoll([arg UTF8String], NULL, 0);
	
	if (errno)
		errx(EXIT_FAILURE, "error converting offset: %s", [arg UTF8String]);
	
	return [NSNumber numberWithLongLong:value];
}

NSData * parse_hex_arg(NSString *arg) {

	NSData *data = HexToData(arg);

	if (!data)
		errx(EXIT_FAILURE, "error converting hex: %s", [arg UTF8String]);

	return data;
}

void print_usage(FILE *outfile, const char * progname) {
	
	fprintf(outfile, "usage: %s [-m] [-r] [-i offset newbytes] [[-s offset newbytes] | [-f oldbytes newbytes]] [-o outfile] file \n", progname);
	fprintf(outfile, "     -m allow multiple occurences \n");
	fprintf(outfile, "     -o write to outfile instead of modifying file \n");
	fprintf(outfile, "     -i insert newbytes at offset (implies allow resizing) \n");
	fprintf(outfile, "     -s replace bytes starting at offset \n");
	fprintf(outfile, "     -r allow content to be resized \n");
	fprintf(outfile, "     -f search for search_bytes, replace with replace_bytes \n");
}

void exit_usage(NSString *progname, int status) {
	
	FILE *outfile = (status == EXIT_SUCCESS) ? stdout : stderr;
	
	print_usage(outfile, [progname UTF8String]);
	
	exit(status);
}

int main (int argc, char * argv[]) {

	NSUInteger options = 0;
	NSString *inFile = nil;
	NSString *outFile = nil;
	
	
	@autoreleasepool {

		NSError *error;
	    NSArray *args              = [[NSProcessInfo processInfo] arguments];
		NSString *progname         = [[args objectAtIndex:0] lastPathComponent];
		NSMutableArray *transforms = [NSMutableArray array];

		NSCAssert(argc == [args count], @"argc != [arguments count]");
		
		for (NSUInteger i = 1; i < argc; i++) {
		
			NSString *arg = [args objectAtIndex:i];
			
			if ([arg isEqual:@"-h"] || [arg isEqual:@"-?"]) {
				exit_usage(progname, EXIT_SUCCESS);
			}
			else if ([arg isEqual:@"-m"]) {
				options |= AllowMultiples;
			}
			else if ([arg isEqual:@"-r"]) {
				options |= AllowResizing;
			}
			else if ([arg isEqual:@"-o"]) {
				
				if (++i < argc) {
					outFile = [args objectAtIndex:i];
				}
				else {
					warnx("too few arguments for %s", "-o");
					exit_usage(progname, EXIT_FAILURE);
				}
			}
			else if ([arg isEqual:@"-i"] || [arg isEqual:@"-s"]) {
				
				if ((i + 2) < argc) {
					[transforms addObject:arg];
					[transforms addObject: parse_offset_arg( [args objectAtIndex:++i] ) ];
					[transforms addObject: parse_hex_arg(    [args objectAtIndex:++i] ) ];
				}
				else {
					warnx("too few arguments for %s", [arg UTF8String]);
					exit_usage(progname, EXIT_FAILURE);
				}
			}
			else if ([arg isEqual:@"-f"]) {
				
				if ((i + 2) < argc) {
					[transforms addObject:arg];
					[transforms addObject: parse_hex_arg( [args objectAtIndex:++i] ) ];
					[transforms addObject: parse_hex_arg( [args objectAtIndex:++i] ) ];
				}
				else {
					warnx("too few arguments for %s", [arg UTF8String]);
					exit_usage(progname, EXIT_FAILURE);
				}					
			}
			else {
				inFile = arg;
			}
		}
		
		if (!inFile) {
			warnx("missing input file");
			exit_usage(progname, EXIT_FAILURE);
		}
		if (!outFile) outFile = inFile;

		NSMutableData *contents = [NSMutableData dataWithContentsOfFile:inFile options:0 error:&error];
		if (!contents)
			err(EXIT_FAILURE, "open %s", argv[1]);

		for (NSUInteger j = 0; j < [transforms count]; ) {
			
			NSString *option = [transforms objectAtIndex:j++];
			id arg1 = [transforms objectAtIndex:j++];
			id arg2 = [transforms objectAtIndex:j++];
			
			if ([option isEqual:@"-i"]) {
				insert_at_offset(contents, arg1, arg2);
			}
			else if ([option isEqual:@"-s"]) {
				replace_at_offset(contents, arg1, arg2);
			}
			else if ([option isEqual:@"-f"]) {
				find_and_replace(contents, arg1, arg2, options);
			}
			
		}

		if ([contents writeToFile:outFile options:NSDataWritingAtomic error:&error] == NO)
			errx(EXIT_FAILURE, "error writing %s: %s", argv[2], [[error localizedDescription] UTF8String]);
		
	}
    return EXIT_SUCCESS;
}

