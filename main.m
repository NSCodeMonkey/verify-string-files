//
//  main.m
//  verify-string-files
//
//  Created by Daniel Kennett on 22/08/14.
//  For license information, see LICENSE.markdown

#import <Foundation/Foundation.h>

#if !defined(var)
#if defined(__cplusplus)
#define var auto
#else
#define var __auto_type
#endif
#endif

#if !defined(let)
#define let const var
#endif

#pragma mark - Usage

void printUsage() {

    NSString *processName = [[NSProcessInfo processInfo] processName];

    printf("%s by Daniel Kennett\n\n", processName.UTF8String);

	printf("Verifies that localizations of the given strings file contain all\n");
	printf("the master .strings file's keys. Intended to be used with an Xcode\n");
	printf("custom build step. \n\n");

	printf("Usage: %s -path <strings file path>\n", processName.UTF8String);
	printf("       %s [-warning-level <error | warning | note>] \n\n", [@"" stringByPaddingToLength:processName.length
																					withString:@" "
																			   startingAtIndex:0].UTF8String);

	printf("  -path           The path to a valid .strings file. Should be\n");
	printf("                  localized (that is, inside an .lproj folder),\n");
	printf("                  and what's considered the \"base\" strings file\n");
	printf("                  for the project.\n\n");

    printf("  -warning-level  The warning level to use: error, warning or note. \n");
    printf("                  Defaults to error.\n");

    printf("\n\n");
}

#pragma mark - Finding Other Files

/** Returns a dictionary of full strings files paths keyed be language code */
NSDictionary *stringsFilesMatchingMasterPath(NSString *masterPath) {

	NSString *basePath = nil;
	NSString *lProjSubPath = nil;

	NSMutableArray *subPathComponents = [NSMutableArray new];
	[subPathComponents addObject:[masterPath lastPathComponent]];

	while (YES) {

		masterPath = [masterPath stringByDeletingLastPathComponent];
		if ([[[masterPath lastPathComponent] pathExtension] caseInsensitiveCompare:@"lproj"] == NSOrderedSame) {
			basePath = [masterPath stringByDeletingLastPathComponent];
			lProjSubPath = [subPathComponents componentsJoinedByString:@"/"];
			break;
		} else {
			[subPathComponents insertObject:[masterPath lastPathComponent] atIndex:0];
		}
	}

	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtPath:basePath];
	NSMutableDictionary *stringsFiles = [NSMutableDictionary new];

	NSString *baseFileName = nil;
	while ((baseFileName = [enumerator nextObject])) {

		NSString *baseFilePath = [basePath stringByAppendingPathComponent:baseFileName];
#if 0
		if ([baseFilePath caseInsensitiveCompare:masterPath] == NSOrderedSame) {
			// Skip original file
			continue;
		}
#endif

		BOOL isDirectory = NO;
		[fileManager fileExistsAtPath:baseFilePath isDirectory:&isDirectory];

		if (isDirectory && [[baseFileName pathExtension] caseInsensitiveCompare:@"lproj"] == NSOrderedSame) {

			NSString *stringsFilePath = [baseFilePath stringByAppendingPathComponent:lProjSubPath];
			if ([fileManager fileExistsAtPath:stringsFilePath]) {
				[stringsFiles setObject:stringsFilePath forKey:baseFileName];
			}
		}

		if (isDirectory) {
			[enumerator skipDescendants];
		}
	}

	if (stringsFiles.count > 0) {
		return [NSDictionary dictionaryWithDictionary:stringsFiles];
	} else {
		return nil;
	}
}

NSDictionary *contentsOfStringsFile(NSString *filePath) {

	NSError *error = nil;
	NSData *plistData = [NSData dataWithContentsOfFile:filePath
											   options:0
												 error:&error];

	if (error != nil) {
		printf("ERROR: Reading file failed with error: %s\n", error.localizedDescription.UTF8String);
		exit(EXIT_FAILURE);
	}

	id plist = [NSPropertyListSerialization propertyListWithData:plistData
														 options:0
														  format:nil
														   error:&error];

	if (error != nil) {
		printf("ERROR: Reading file failed with error: %s\n", error.localizedDescription.UTF8String);
		exit(EXIT_FAILURE);
	}

	if (![plist isKindOfClass:[NSDictionary class]]) {
		printf("ERROR: Strings file contained unexpected root object type.");
		exit(EXIT_FAILURE);
	}

	return plist;
}

NSDictionary *allStringsFiles(NSString *masterPath) {

	NSDictionary *otherStringsFilePaths = stringsFilesMatchingMasterPath(masterPath);
	NSMutableDictionary *stringsFileContents = [NSMutableDictionary new];

	for (NSString *language in otherStringsFilePaths) {

		NSDictionary *strings = contentsOfStringsFile(otherStringsFilePaths[language]);
		if (strings) {
			[stringsFileContents setObject:strings forKey:language];
		}
	}

	if (stringsFileContents.count > 0) {
		return [NSDictionary dictionaryWithDictionary:stringsFileContents];
	} else {
		return nil;
	}
}

NSDictionary *checkForMissingKeys(NSDictionary<NSString*, NSDictionary*> *stringsByLanguage) {

	NSMutableDictionary *problems = [NSMutableDictionary new];
    
    let allKeys = [NSMutableSet set];
    [stringsByLanguage enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull language, NSDictionary * _Nonnull strings, BOOL * _Nonnull stop) {
        [allKeys addObjectsFromArray:strings.allKeys];
    }];

    [stringsByLanguage enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull language, NSDictionary * _Nonnull strings, BOOL * _Nonnull stop) {
        let keys = [NSSet setWithArray:strings.allKeys];
        NSMutableSet* missingKeys = [allKeys mutableCopy];
        [missingKeys minusSet:keys];
        
        if (missingKeys.count > 0) {
            problems[language] = missingKeys;
        }
    }];

	if (problems.count > 0) {
		return [NSDictionary dictionaryWithDictionary:problems];
	} else {
		return nil;
	}
}

#pragma mark - Output

NSUInteger lineNumberForKeyInStringsFile(NSString *key, NSString *stringsFilePath) {

	static NSMutableDictionary *stringsFileCache = nil;

	if (stringsFileCache == nil) {
		stringsFileCache = [NSMutableDictionary new];
	}

	NSString *fileContents = stringsFileCache[stringsFilePath];
	if (fileContents == nil) {
		fileContents = [[NSString alloc] initWithContentsOfFile:stringsFilePath usedEncoding:nil error:nil];
		stringsFileCache[stringsFilePath] = fileContents;
	}

	if (fileContents.length == 0) {
		return 1;
	}

	NSArray *lines = [fileContents componentsSeparatedByString:@"\n"];
	for (NSUInteger lineIndex = 0; lineIndex < lines.count; lineIndex++) {
		NSString *line = lines[lineIndex];
		if ([line rangeOfString:key].location != NSNotFound) {
			return lineIndex + 1;
		}
	}

	return 1;
}

void logMissingKeys(NSString *masterStringsFilePath, NSDictionary *missingKeys, NSString *warningLevel) {

	for (NSString *masterKey in missingKeys) {

		NSUInteger keyLine = lineNumberForKeyInStringsFile(masterKey, masterStringsFilePath);
		NSArray *missingLanguages = missingKeys[masterKey];

		for (NSString *language in missingLanguages) {
			fprintf(stderr, "%s:%lu: %s: %s is missing in %s\n",
					masterStringsFilePath.UTF8String,
					(unsigned long)keyLine,
					warningLevel.UTF8String,
					masterKey.UTF8String,
					language.UTF8String);
		}
	}
}

#pragma mark - Main

BOOL warningLevelIsValid(NSString *warningLevel) {
	return [warningLevel isEqualToString:@"error"] ||
	[warningLevel isEqualToString:@"warning"] ||
	[warningLevel isEqualToString:@"note"];
}

int main(int argc, const char * argv[])
{

    @autoreleasepool {

        NSString *inputDirPath = [[NSUserDefaults standardUserDefaults] valueForKey:@"path"];
		NSString *warningLevel = [[NSUserDefaults standardUserDefaults] valueForKey:@"warning-level"];
		if (warningLevel.length == 0) {
			warningLevel = @"error";
		}

        setbuf(stdout, NULL);

        if (inputDirPath.length == 0 || !warningLevelIsValid(warningLevel)) {
            printUsage();
            exit(EXIT_FAILURE);
        }

        if (![[NSFileManager defaultManager] fileExistsAtPath:inputDirPath]) {
            printf("ERROR: Input file %s doesn't exist.\n", [inputDirPath UTF8String]);
            exit(EXIT_FAILURE);
        }

		NSDictionary *allStrings = allStringsFiles(inputDirPath);
		NSDictionary *missingKeys = checkForMissingKeys(allStrings);
		logMissingKeys(inputDirPath, missingKeys, warningLevel);

        exit(EXIT_SUCCESS);

    }
    return 0;
}
