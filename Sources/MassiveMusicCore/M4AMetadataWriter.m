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

BOOL MassiveMusicWriteM4AHeader(
    NSURL *url,
    NSDictionary<NSString *, id> *info,
    NSError **error
) {
    AVMutableMovie *movie = [AVMutableMovie movieWithURL:url options:nil];
    if (movie == nil) {
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
    return [movie writeMovieHeaderToURL:url
                               fileType:AVFileTypeAppleM4A
                                options:AVMovieWritingAddMovieHeaderToDestination
                                  error:error];
}
