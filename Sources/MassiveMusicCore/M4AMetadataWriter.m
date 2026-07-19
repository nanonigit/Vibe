#import <AVFoundation/AVFoundation.h>
#import "MassiveMusicCore-Bridging-Header.h"

static AVMutableMetadataItem *MassiveMusicStringItem(AVMetadataIdentifier identifier, NSString *value) {
    AVMutableMetadataItem *item = [[AVMutableMetadataItem alloc] init];
    item.identifier = identifier;
    item.value = value;
    item.extendedLanguageTag = @"und";
    return item;
}

static AVMutableMetadataItem *MassiveMusicNumberItem(AVMetadataIdentifier identifier, NSNumber *number) {
    uint16_t value = CFSwapInt16HostToBig((uint16_t)number.unsignedIntegerValue);
    uint16_t fields[4] = { 0, value, 0, 0 };
    AVMutableMetadataItem *item = [[AVMutableMetadataItem alloc] init];
    item.identifier = identifier;
    // `trkn` contains four 16-bit fields; `disk` contains three.
    NSUInteger length = [identifier isEqualToString:AVMetadataIdentifieriTunesMetadataDiscNumber]
        ? sizeof(uint16_t) * 3 : sizeof(fields);
    item.value = [NSData dataWithBytes:fields length:length];
    return item;
}

static NSNumber *MassiveMusicNumberValue(AVMetadataItem *item) {
    NSData *data = item.dataValue;
    if (data.length < sizeof(uint16_t) * 2) {
        return item.numberValue;
    }
    // NSData does not promise uint16_t alignment. Copy the two big-endian
    // fields before decoding instead of dereferencing a potentially unaligned
    // pointer on Apple Silicon.
    uint16_t fields[2] = {0, 0};
    [data getBytes:fields length:sizeof(fields)];
    return @(CFSwapInt16BigToHost(fields[1]));
}

static BOOL MassiveMusicExportM4AWithMetadata(
    NSURL *sourceURL,
    NSURL *destinationURL,
    NSArray<AVMetadataItem *> *metadata,
    NSError **error
) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
    AVAssetExportSession *session = [[AVAssetExportSession alloc]
        initWithAsset:asset presetName:AVAssetExportPresetPassthrough];
    if (session == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"MassiveMusic.M4AMetadataWriter"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"M4Aの安全なパススルー書き出しを開始できませんでした。"}];
        }
        return NO;
    }
    session.outputURL = destinationURL;
    session.outputFileType = AVFileTypeAppleM4A;
    session.metadata = metadata;
    session.shouldOptimizeForNetworkUse = NO;

    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    [session exportAsynchronouslyWithCompletionHandler:^{
        dispatch_semaphore_signal(finished);
    }];
    dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
    if (session.status != AVAssetExportSessionStatusCompleted) {
        if (error != NULL) {
            *error = session.error ?: [NSError errorWithDomain:@"MassiveMusic.M4AMetadataWriter"
                                                          code:4
                                                      userInfo:@{NSLocalizedDescriptionKey: @"M4Aの安全なパススルー書き出しに失敗しました。"}];
        }
        return NO;
    }
    return YES;
}

NSDictionary<NSString *, id> *MassiveMusicReadM4AMetadata(NSURL *url, NSError **error) {
    AVMutableMovie *movie = [AVMutableMovie movieWithURL:url options:nil];
    if (movie == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"MassiveMusic.M4AMetadataWriter"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"M4Aメタデータを読み込めませんでした。"}];
        }
        return nil;
    }
    NSDictionary<AVMetadataIdentifier, NSString *> *stringKeys = @{
        AVMetadataIdentifieriTunesMetadataSongName: @"title",
        AVMetadataIdentifieriTunesMetadataArtist: @"artist",
        AVMetadataIdentifieriTunesMetadataAlbum: @"album",
        AVMetadataIdentifieriTunesMetadataAlbumArtist: @"album artist",
        AVMetadataIdentifieriTunesMetadataUserGenre: @"genre"
    };
    NSMutableDictionary<NSString *, id> *info = [[NSMutableDictionary alloc] init];
    for (AVMetadataItem *item in movie.metadata) {
        NSString *key = item.identifier == nil ? nil : stringKeys[item.identifier];
        if (key != nil && item.stringValue != nil) {
            info[key] = item.stringValue;
        } else if ([item.identifier isEqualToString:AVMetadataIdentifieriTunesMetadataTrackNumber]) {
            NSNumber *value = MassiveMusicNumberValue(item);
            if (value != nil) info[@"track number"] = value.stringValue;
        } else if ([item.identifier isEqualToString:AVMetadataIdentifieriTunesMetadataDiscNumber]) {
            NSNumber *value = MassiveMusicNumberValue(item);
            if (value != nil) info[@"disc number"] = value.stringValue;
        }
    }
    return info;
}

BOOL MassiveMusicWriteM4AHeader(
    NSURL *url,
    NSDictionary<NSString *, id> *info,
    NSError **error
) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *fallbackInputURL = [fileManager.temporaryDirectory
        URLByAppendingPathComponent:[NSString stringWithFormat:@"Vibe-M4A-input-%@.m4a", NSUUID.UUID.UUIDString]];
    NSURL *fallbackOutputURL = [fileManager.temporaryDirectory
        URLByAppendingPathComponent:[NSString stringWithFormat:@"Vibe-M4A-output-%@.m4a", NSUUID.UUID.UUIDString]];
    NSError *copyError = nil;
    if (![fileManager copyItemAtURL:url toURL:fallbackInputURL error:&copyError]) {
        if (error != NULL) *error = copyError;
        return NO;
    }

    AVMutableMovie *movie = [AVMutableMovie movieWithURL:url options:nil];
    if (movie == nil) {
        [fileManager removeItemAtURL:fallbackInputURL error:nil];
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"MassiveMusic.M4AMetadataWriter"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"M4Aヘッダーを読み込めませんでした。"}];
        }
        return NO;
    }

    NSSet<AVMetadataIdentifier> *replacedIdentifiers = [NSSet setWithArray:@[
        AVMetadataIdentifieriTunesMetadataSongName,
        AVMetadataIdentifieriTunesMetadataArtist,
        AVMetadataIdentifieriTunesMetadataAlbum,
        AVMetadataIdentifieriTunesMetadataAlbumArtist,
        AVMetadataIdentifieriTunesMetadataUserGenre,
        AVMetadataIdentifieriTunesMetadataTrackNumber,
        AVMetadataIdentifieriTunesMetadataDiscNumber
    ]];
    NSMutableArray<AVMetadataItem *> *metadata = [[NSMutableArray alloc] init];
    for (AVMetadataItem *item in movie.metadata) {
        if (item.identifier == nil || ![replacedIdentifiers containsObject:item.identifier]) {
            [metadata addObject:item];
        }
    }

    NSArray<NSArray *> *stringFields = @[
        @[ @"title", AVMetadataIdentifieriTunesMetadataSongName ],
        @[ @"artist", AVMetadataIdentifieriTunesMetadataArtist ],
        @[ @"album", AVMetadataIdentifieriTunesMetadataAlbum ],
        @[ @"album artist", AVMetadataIdentifieriTunesMetadataAlbumArtist ],
        @[ @"genre", AVMetadataIdentifieriTunesMetadataUserGenre ]
    ];
    for (NSArray *field in stringFields) {
        NSString *value = info[field[0]];
        if ([value isKindOfClass:NSString.class] && value.length > 0) {
            [metadata addObject:MassiveMusicStringItem(field[1], value)];
        }
    }
    NSNumber *track = info[@"track number"];
    if ([track isKindOfClass:NSNumber.class]) {
        [metadata addObject:MassiveMusicNumberItem(AVMetadataIdentifieriTunesMetadataTrackNumber, track)];
    }
    NSNumber *disc = info[@"disc number"];
    if ([disc isKindOfClass:NSNumber.class]) {
        [metadata addObject:MassiveMusicNumberItem(AVMetadataIdentifieriTunesMetadataDiscNumber, disc)];
    }

    movie.metadata = metadata;
    NSError *headerError = nil;
    BOOL wroteHeader = [movie writeMovieHeaderToURL:url
                                           fileType:AVFileTypeAppleM4A
                                            options:AVMovieWritingAddMovieHeaderToDestination
                                              error:&headerError];
    if (wroteHeader) {
        [fileManager removeItemAtURL:fallbackInputURL error:nil];
        return YES;
    }

    // Some valid M4A files contain vendor-specific atoms that AVMutableMovie can
    // read but refuses to rewrite in place. Export from the untouched fallback
    // copy with the passthrough preset so encoded audio packets are not re-encoded.
    NSError *fallbackError = nil;
    BOOL exported = MassiveMusicExportM4AWithMetadata(
        fallbackInputURL, fallbackOutputURL, metadata, &fallbackError
    );
    if (exported) {
        NSError *replaceError = nil;
        exported = [fileManager replaceItemAtURL:url
                                   withItemAtURL:fallbackOutputURL
                                  backupItemName:nil
                                         options:0
                                resultingItemURL:nil
                                           error:&replaceError];
        if (!exported) fallbackError = replaceError;
    }
    [fileManager removeItemAtURL:fallbackInputURL error:nil];
    [fileManager removeItemAtURL:fallbackOutputURL error:nil];
    if (!exported && error != NULL) {
        *error = fallbackError ?: headerError;
    }
    return exported;
}
