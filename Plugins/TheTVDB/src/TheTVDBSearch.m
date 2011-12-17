//
//  TheTVDBSearch.m
//  MetaZ
//
//  Created by Nigel Graham on 10/04/10.
//  Copyright 2010 Maven-Group. All rights reserved.
//

#import "TheTVDBSearch.h"
#import "Access.h"
#import "TheTVDBPlugin.h"


@implementation TheTVDBSearch

+ (id)searchWithProvider:(id)provider delegate:(id<MZSearchProviderDelegate>)delegate queue:(NSOperationQueue *)queue
{
    return [[[self alloc] initWithProvider:provider delegate:delegate queue:queue] autorelease];
}

- (id)initWithProvider:(id)theProvider delegate:(id<MZSearchProviderDelegate>)theDelegate queue:(NSOperationQueue *)theQueue
{
    self = [super init];
    if(self)
    {
        provider = theProvider;
        delegate = [theDelegate retain];
        queue = [theQueue retain];
    }
    return self;
}

- (void)dealloc
{
    [delegate release];
    [queue release];
    [mirrorRequest release];
    [super dealloc];
}

@synthesize provider;
@synthesize delegate;
@synthesize season;
@synthesize episode;

- (void)queueOperation:(NSOperation *)operation
{
    [self addOperation:operation];
    [queue addOperation:operation];
}

- (void)operationsFinished
{
    [delegate searchFinished];
}

- (void)updateMirror;
{
    NSURL* url = [NSURL URLWithString:[NSString
            stringWithFormat:@"http://www.thetvdb.com/api/%@/mirrors.xml",
                THETVDB_API_KEY]];

    mirrorRequest = [[ASIHTTPRequest alloc] initWithURL:url];
    [mirrorRequest setDelegate:self];
    mirrorRequest.didFinishSelector = @selector(updateMirrorCompleted:);
    mirrorRequest.didFailSelector = @selector(updateMirrorFailed:);

    [self addOperation:mirrorRequest];
}

- (void)updateMirrorCompleted:(id)request;
{
    ASIHTTPRequest* theRequest = request;
    MZLoggerDebug(@"Got response from cache %@", [theRequest didUseCachedResponse] ? @"YES" : @"NO");
    //MZLoggerDebug(@"Got amazon response:\n%@", [theWrapper responseAsText]);
    NSXMLDocument* doc = [[[NSXMLDocument alloc] initWithXMLString:[theRequest responseString] options:0 error:NULL] autorelease];
    
    NSMutableArray* bannermirrors = [NSMutableArray array]; 
    NSMutableArray* xmlmirrors = [NSMutableArray array]; 
 
    NSArray* items = [doc nodesForXPath:@"/Mirrors/Mirror" error:NULL];
    for(NSXMLElement* item in items)
    {
        NSInteger typemask = [[item stringForXPath:@"typemask" error:NULL] integerValue];
        NSString* mirrorpath = [item stringForXPath:@"mirrorpath" error:NULL];
        if((typemask & 1) == 1)
            [xmlmirrors addObject:mirrorpath];
        if((typemask & 2) == 2)
            [bannermirrors addObject:mirrorpath];
    }
    
    srandom(time(NULL));
    if([bannermirrors count] == 0)
        bannerMirror = @"http://www.thetvdb.com";
    else if([bannermirrors count] == 1)
        bannerMirror = [[bannermirrors objectAtIndex:0] retain];
    else {
        int idx = random() % [bannermirrors count];
        bannerMirror = [[bannermirrors objectAtIndex:idx] retain];
    }
    
    if([xmlmirrors count] == 0)
        xmlMirror = @"http://www.thetvdb.com";
    else if([xmlmirrors count] == 1)
        xmlMirror = [[xmlmirrors objectAtIndex:0] retain];
    else {
        int idx = random() % [xmlmirrors count];
        xmlMirror = [[xmlmirrors objectAtIndex:idx] retain];
    }
}

- (void)updateMirrorFailed:(id)request;
{
    ASIHTTPRequest* theRequest = request;
    MZLoggerDebug(@"Request failed with status code %d", [theRequest responseStatusCode]);

    bannerMirror = @"http://www.thetvdb.com";
    xmlMirror = @"http://www.thetvdb.com";
}


- (void)fetchSeriesByName:(NSString *)name
{
    NSString* url = @"http://www.thetvdb.com/api/GetSeries.php";
    NSDictionary* p = [NSDictionary dictionaryWithObjectsAndKeys:name, @"seriesname", @"en", @"language", nil];

    NSString* params = [NSString mz_queryStringForParameterDictionary:p];
    NSString *urlWithParams = [url stringByAppendingFormat:@"?%@", params];
    
    ASIHTTPRequest* request = [[ASIHTTPRequest alloc] initWithURL:[NSURL URLWithString:urlWithParams]];
    [request setDelegate:self];
    request.didFinishSelector = @selector(fetchSeriesCompleted:);
    request.didFailSelector = @selector(fetchSeriesFailed:);
    
    if(mirrorRequest)
        [request addDependency:mirrorRequest];

    [self addOperation:request];
    [request release];
}

- (void)fetchSeriesCompleted:(id)request;
{
    ASIHTTPRequest* theRequest = request;
    MZLoggerDebug(@"Got response from cache %@", [theRequest didUseCachedResponse] ? @"YES" : @"NO");
    NSXMLDocument* doc = [[[NSXMLDocument alloc] initWithXMLString:[theRequest responseString] options:0 error:NULL] autorelease];

    NSArray* items = [doc nodesForXPath:@"/Data/Series" error:NULL];
    MZLoggerDebug(@"Got TheTVDB series %d", [items count]);
    for(NSXMLElement* item in items)
    {
        NSString* seriesStr = [item stringForXPath:@"seriesid" error:NULL];
        NSUInteger series = [seriesStr integerValue];

        [self fetchFullSeries:series];
    }
}

- (void)fetchSeriesFailed:(id)request;
{
    ASIHTTPRequest* theRequest = request;
    MZLoggerDebug(@"Request failed with status code %d", [theRequest responseStatusCode]);
}

- (void)fetchSeriesBannersCompleted:(id)request;
{
    ASIHTTPRequest* theRequest = request;
    MZLoggerDebug(@"Got response from cache %@", [theRequest didUseCachedResponse] ? @"YES" : @"NO");
    
    NSXMLDocument* doc = [[[NSXMLDocument alloc] initWithXMLString:[theRequest responseString] options:0 error:NULL] autorelease];

}

- (void)fetchSeriesBannersFailed:(id)request;
{
    ASIHTTPRequest* theRequest = request;
    MZLoggerDebug(@"Request failed with status code %d", [theRequest responseStatusCode]);
}

- (void)fetchFullSeries:(NSUInteger)theSeries;
{
    NSString* urlStr = [NSString stringWithFormat:@"%@/api/%@/series/%d/all/en.xml",
            xmlMirror,
            THETVDB_API_KEY,
            theSeries];
    NSURL* url = [NSURL URLWithString:urlStr];
    ASIHTTPRequest* request = [[ASIHTTPRequest alloc] initWithURL:url];
    [request setDelegate:self];
    request.didFinishSelector = @selector(fetchFullSeriesCompleted:);
    request.didFailSelector = @selector(fetchFullSeriesFailed:);

    NSMutableDictionary* userInfo = [NSMutableDictionary dictionary];
    [userInfo setObject:[NSNumber numberWithUnsignedInteger:theSeries] forKey:@"series"];
    request.userInfo = userInfo;
    
    NSString* bannerUrl = [NSString stringWithFormat:@"%@/api/%@/series/%d/banners.xml",
            bannerMirror,
            THETVDB_API_KEY,
            theSeries];
    ASIHTTPRequest* bannerRequest = [[ASIHTTPRequest alloc] initWithURL:[NSURL URLWithString:bannerUrl]];
    [bannerRequest setDelegate:self];
    bannerRequest.didFinishSelector = @selector(fetchSeriesBannersCompleted:);
    bannerRequest.didFailSelector = @selector(fetchSeriesBannersFailed:);
    bannerRequest.userInfo = userInfo;
    [request addDependency:bannerRequest];
    [self queueOperation:bannerRequest];
    [bannerRequest release];
    
    [self queueOperation:request];
    [request release];
}

- (void)fetchFullSeriesCompleted:(id)request;
{
    ASIHTTPRequest* theRequest = request;
    NSDictionary* userInfo = [theRequest userInfo];
    NSUInteger series = [[userInfo objectForKey:@"series"] unsignedIntegerValue];

    MZLoggerDebug(@"Got response from cache %@", [theRequest didUseCachedResponse] ? @"YES" : @"NO");
 

    //MZLoggerDebug(@"Got response:\n%@", [theWrapper responseAsText]);
    NSXMLDocument* doc = [[[NSXMLDocument alloc] initWithXMLString:[theRequest responseString] options:0 error:NULL] autorelease];

    NSMutableDictionary* seriesDict = [NSMutableDictionary dictionary];

    NSString* tvShow = [doc stringForXPath:@"/Data/Series/SeriesName" error:NULL];
    MZTag* tvShowTag = [MZTag tagForIdentifier:MZTVShowTagIdent];
    [seriesDict setObject:[tvShowTag objectFromString:tvShow] forKey:MZTVShowTagIdent];
    MZTag* artistTag = [MZTag tagForIdentifier:MZArtistTagIdent];
    [seriesDict setObject:[artistTag objectFromString:tvShow] forKey:MZArtistTagIdent];

    NSString* tvNetwork = [doc stringForXPath:@"/Data/Series/Network" error:NULL];
    if(tvNetwork && [tvNetwork length] > 0)
    {
        MZTag* tvNetworkTag = [MZTag tagForIdentifier:MZTVNetworkTagIdent];
        [seriesDict setObject:[tvNetworkTag objectFromString:tvNetwork] forKey:MZTVNetworkTagIdent];
    }
    
    NSString* rating = [doc stringForXPath:@"/Data/Series/ContentRating" error:NULL];
    MZTag* ratingTag = [MZTag tagForIdentifier:MZRatingTagIdent];
    NSNumber* ratingNr = [ratingTag objectFromString:rating];
    if([ratingNr intValue] != MZNoRating)
        [seriesDict setObject:ratingNr forKey:MZRatingTagIdent];

    NSString* actorStr = [doc stringForXPath:@"/Data/Series/Actors" error:NULL];
    NSArray* actors1 = [actorStr componentsSeparatedByString:@"|"];
    NSMutableArray* actors = [NSMutableArray array];
    for(NSString* str in actors1)
    {
        NSString* str2 = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if([str2 length] > 0)
            [actors addObject:str2];
    }
    if([actors count] > 0)
        [seriesDict setObject:[actors componentsJoinedByString:@", "] forKey:MZActorsTagIdent];
    
    
    NSString* genreStr = [doc stringForXPath:@"/Data/Series/Genre" error:NULL];
    NSArray* genres1 = [genreStr componentsSeparatedByString:@"|"];
    NSMutableArray* genres = [NSMutableArray array];
    for(NSString* str in genres1)
    {
        NSString* str2 = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if([str2 length] > 0)
            [genres addObject:str2];
    }
    if([genres count] > 0)
        [seriesDict setObject:[genres objectAtIndex:0] forKey:MZGenreTagIdent];

    NSString* imdbId = [doc stringForXPath:@"/Data/Series/IMDB_ID" error:NULL];
    if(imdbId && [imdbId length] > 0)
    {
        MZTag* imdbTag = [MZTag tagForIdentifier:MZIMDBTagIdent];
        [seriesDict setObject:[imdbTag objectFromString:imdbId] forKey:MZIMDBTagIdent];
    }
    
    
    NSMutableArray* results = [NSMutableArray array];

    NSArray* items = [doc nodesForXPath:@"/Data/Episode" error:NULL];
    MZLoggerDebug(@"Got TheTVDB series %d", [items count]);
    for(NSXMLElement* item in items)
    {
        NSString* seasonNo = [item stringForXPath:@"SeasonNumber" error:NULL];
        if([seasonNo integerValue] != season)
            continue;
            
        NSString* episodeNo = [item stringForXPath:@"EpisodeNumber" error:NULL];
        if(episode>=0 && [episodeNo integerValue] != episode)
            continue;


        NSMutableDictionary* episodeDict = [NSMutableDictionary dictionaryWithDictionary:seriesDict];
    
        if(seasonNo && [seasonNo length] > 0)
        {
            MZTag* tag = [MZTag tagForIdentifier:MZTVSeasonTagIdent];
            [episodeDict setObject:[tag objectFromString:seasonNo] forKey:MZTVSeasonTagIdent];
        }

        if(episodeNo && [episodeNo length] > 0)
        {
            MZTag* tag = [MZTag tagForIdentifier:MZTVEpisodeTagIdent];
            [episodeDict setObject:[tag objectFromString:episodeNo] forKey:MZTVEpisodeTagIdent];
        }

        [episodeDict setObject:[NSNumber numberWithUnsignedInt:series] forKey:TVDBSeriesIdTagIdent];
        NSString* seasonId = [item stringForXPath:@"seasonid" error:NULL];
        [episodeDict setObject:seasonId forKey:TVDBSeasonIdTagIdent];
        NSString* episodeId = [item stringForXPath:@"id" error:NULL];
        [episodeDict setObject:episodeId forKey:TVDBEpisodeIdTagIdent];

        NSString* title = [item stringForXPath:@"EpisodeName" error:NULL];
        if(title && [title length] > 0)
        {
            MZTag* tag = [MZTag tagForIdentifier:MZTitleTagIdent];
            [episodeDict setObject:[tag objectFromString:title] forKey:MZTitleTagIdent];
        }

        NSString* directorStr = [item stringForXPath:@"Director" error:NULL];
        NSArray* directors1 = [directorStr componentsSeparatedByString:@"|"];
        NSMutableArray* directors = [NSMutableArray array];
        for(NSString* str in directors1)
        {
            NSString* str2 = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if([str2 length] > 0)
                [directors addObject:str2];
        }
        if([directors count] > 0)
            [episodeDict setObject:[directors componentsJoinedByString:@", "] forKey:MZDirectorTagIdent];

        NSString* writerStr = [item stringForXPath:@"Writer" error:NULL];
        NSArray* writers1 = [writerStr componentsSeparatedByString:@"|"];
        NSMutableArray* writers = [NSMutableArray array];
        for(NSString* str in writers1)
        {
            NSString* str2 = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if([str2 length] > 0)
                [writers addObject:str2];
        }
        if([writers count] > 0)
            [episodeDict setObject:[writers componentsJoinedByString:@", "] forKey:MZScreenwriterTagIdent];

        NSString* description = [item stringForXPath:@"Overview" error:NULL];
        if(description && [description length] > 0)
        {
            [episodeDict setObject:description forKey:MZShortDescriptionTagIdent];
            [episodeDict setObject:description forKey:MZLongDescriptionTagIdent];
        }

        NSString* productionCode = [item stringForXPath:@"ProductionCode" error:NULL];
        if(productionCode && [productionCode length] > 0)
        {
            MZTag* tag = [MZTag tagForIdentifier:MZTVEpisodeIDTagIdent];
            [episodeDict setObject:[tag objectFromString:productionCode] forKey:MZTVEpisodeIDTagIdent];
        }

        NSString* release = [item stringForXPath:@"FirstAired" error:NULL];
        if( release && [release length] > 0 )
        {
            NSDate* date;// = [NSDate dateWithUTCString:release];
            //if(!date)
            {
                NSDateFormatter* format = [[[NSDateFormatter alloc] init] autorelease];
                format.dateFormat = @"yyyy-MM-dd";
                date = [format dateFromString:release];
            }
            if(date) 
                [episodeDict setObject:date forKey:MZDateTagIdent];
            else
                MZLoggerError(@"Unable to parse release date '%@'", release);
        }

        NSString* dvdSeasonStr = [item stringForXPath:@"DVD_season" error:NULL];
        if(dvdSeasonStr && [dvdSeasonStr length] > 0)
        {
            MZTag* dvdSeasonTag = [MZTag tagForIdentifier:MZDVDSeasonTagIdent];
            [episodeDict setObject:[dvdSeasonTag objectFromString:dvdSeasonStr] forKey:MZDVDSeasonTagIdent];
        }

        NSString* dvdEpisodeStr = [item stringForXPath:@"DVD_episodenumber" error:NULL];
        if(dvdEpisodeStr && [dvdEpisodeStr length] > 0)
        {
            MZTag* dvdEpisodeTag = [MZTag tagForIdentifier:MZDVDEpisodeTagIdent];
            [episodeDict setObject:[dvdEpisodeTag objectFromString:dvdEpisodeStr] forKey:MZDVDEpisodeTagIdent];
        }

        NSString* imdbId = [item stringForXPath:@"IMDB_ID" error:NULL];
        if(imdbId && [imdbId length] > 0)
        {
            MZTag* imdbTag = [MZTag tagForIdentifier:MZIMDBTagIdent];
            [episodeDict setObject:[imdbTag objectFromString:imdbId] forKey:MZIMDBTagIdent];
        }
        
        
        MZSearchResult* result = [MZSearchResult resultWithOwner:provider dictionary:episodeDict];
        [results addObject:result];
    }
    
    MZLoggerDebug(@"Parsed TheTVDB results %d", [results count]);
    [delegate searchProvider:provider result:results];
}

- (void)fetchFullSeriesFailed:(id)request;
{
    ASIHTTPRequest* theRequest = request;
    MZLoggerDebug(@"Request failed with status code %d", [theRequest responseStatusCode]);
}

@end

