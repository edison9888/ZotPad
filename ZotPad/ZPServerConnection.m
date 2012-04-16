//
//  ZPServerConnection.m
//  ZotPad
//
//  Created by Rönkkö Mikko on 11/21/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//


#include <sys/xattr.h>

//Some of these are needed to determine if network connection is available.
//TODO: determine which and clean up
#import <sys/socket.h>
#import <netinet/in.h>
#import <netinet6/in6.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>

#import <SystemConfiguration/SystemConfiguration.h>

#import "ZPAppDelegate.h"
#import "ZPServerConnection.h"
#import "ZPAuthenticationDialog.h"
#import "ZPServerResponseXMLParser.h"
#import "ZPServerResponseXMLParserItem.h"
#import "ZPServerResponseXMLParserLibrary.h"
#import "ZPServerResponseXMLParserCollection.h"
#import "ZPAuthenticationProcess.h"
#import "ZPZoteroItem.h"
#import "ZPZoteroCollection.h"
#import "ZPZoteroLibrary.h"
#import "ZPZoteroNote.h"
#import "ZPZoteroAttachment.h"
#import "ZPDataLayer.h"

#import "ASIHTTPRequest.h"

#import "ZPLogger.h"
#import "ZPPreferences.h"

#import "ZPFileChannel.h"
#import "ZPFileChannel_Dropbox.h"
#import "ZPFileChannel_WebDAV.h"
#import "ZPFileChannel_ZoteroStorage.h"
#import "ZPFileChannel_Samba.h"

//Private methods

@interface ZPServerConnection();
    

-(ZPServerResponseXMLParser*) makeServerRequest:(NSInteger)type withParameters:(NSDictionary*) parameters;

@end


@implementation ZPServerConnection

static ZPServerConnection* _instance = nil;

const NSInteger ZPServerConnectionRequestGroups = 1;
const NSInteger ZPServerConnectionRequestCollections = 2;
const NSInteger ZPServerConnectionRequestSingleCollection = 3;
const NSInteger ZPServerConnectionRequestItems = 4;
const NSInteger ZPServerConnectionRequestItemsAndChildren = 5;
const NSInteger ZPServerConnectionRequestSingleItem = 6;
const NSInteger ZPServerConnectionRequestSingleItemChildren = 7;
const NSInteger ZPServerConnectionRequestKeys = 8;
const NSInteger ZPServerConnectionRequestTopLevelKeys = 9;

-(id)init
{
    self = [super init];
        
    _activeRequestCount = 0;
    _fileChannels = [NSArray arrayWithObjects:[[ZPFileChannel_WebDAV alloc] init], 
                     [[ZPFileChannel_ZoteroStorage alloc] init], 
                     [[ZPFileChannel_Dropbox alloc] init], 
                     [[ZPFileChannel_Samba alloc] init], nil];
    return self;
}

/*

 Singleton accessor. If ZotPad is offline or there is no internet connection, return null to prevent accessing the server.
 
 */

+(ZPServerConnection*) instance {
    if([[ZPPreferences instance] online]){
        if(_instance == NULL){
            _instance = [[ZPServerConnection alloc] init];
        }
        if([_instance hasInternetConnection]) return _instance;
           
    }
    
    return NULL;
}

//Adapted from the Reachability example project

-(BOOL) hasInternetConnection{
    
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr*) &zeroAddress);
    SCNetworkReachabilityFlags flags;
    BOOL success = SCNetworkReachabilityGetFlags(reachability, &flags);
    BOOL online = success && (flags & kSCNetworkFlagsReachable) && !(flags & kSCNetworkFlagsConnectionRequired);
    CFRelease(reachability);

    return online;
}

/*
 We assume that the client is authenticated if a oauth key exists. The key will be cleared if we notice that it is not valid while using it.
 */

- (BOOL) authenticated{
    
    return([[ZPPreferences instance] OAuthKey] != nil);
    
}

-(NSData*) _retrieveDataFromServer:(NSString*)urlString{
    _activeRequestCount++;
    
    NSLog(@"Request started: %@ Active queries: %i",urlString,_activeRequestCount);
    
    //TODO: Fix the network activity indicator. It does not always get activated because it activates and deactivates in the same method call.
    
    //First request starts the network indicator
    if(_activeRequestCount==1) [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
    
    NSURLRequest * urlRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    NSURLResponse * response = nil;
    NSError* error = nil;
    NSData* responseData= [NSURLConnection sendSynchronousRequest:urlRequest returningResponse:&response error:&error];

    //If we receive a 403 (forbidden) error, delete the authorization key because we know that it is
    //no longer valid.
    if([(NSHTTPURLResponse*)response statusCode]==403){
        NSLog(@"The authorization key is no longer valid.");
        [[ZPPreferences instance] resetUserCredentials];
    }
    
    _activeRequestCount--;
    
    //Last request hides the network indicator
    if(_activeRequestCount==0) [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];

    return responseData;
}


-(ZPServerResponseXMLParser*) makeServerRequest:(NSInteger)type withParameters:(NSDictionary*) parameters{
    
    
    NSData* responseData = NULL;
    NSString* urlString;
   
    NSString* oauthkey =  [[ZPPreferences instance] OAuthKey];
    if(oauthkey!=NULL){

        NSInteger libraryID = [(NSNumber*)[parameters objectForKey:@"libraryID"] integerValue];
        
        if(libraryID==1 || libraryID == 0){
            urlString = [NSString stringWithFormat:@"https://api.zotero.org/users/%@/",[[ZPPreferences instance] userID]];
        }
        else{
            urlString = [NSString stringWithFormat:@"https://api.zotero.org/groups/%i/",libraryID];        
        }
        
        // Groups and collections
        
        if(type==ZPServerConnectionRequestGroups){
            urlString = [NSString stringWithFormat:@"%@groups?key=%@&content=none",urlString,oauthkey];
        }
        else if (type==ZPServerConnectionRequestCollections){
            urlString = [NSString stringWithFormat:@"%@collections?key=%@",urlString,oauthkey];
        }
        else if (type==ZPServerConnectionRequestSingleCollection){
            urlString = [NSString stringWithFormat:@"%@collections/%@?key=%@",urlString,[parameters objectForKey:@"collectionKey"],oauthkey];
        }

        // items
        
        else if (type==ZPServerConnectionRequestItems || type == ZPServerConnectionRequestTopLevelKeys){
            NSString* collectionKey = [parameters objectForKey:@"collectionKey"];
            NSString* format =NULL;
            if(type==ZPServerConnectionRequestItems){
                format = @"atom";
            }
            else{
                format = @"keys";
            }
            if(collectionKey!=NULL){
                urlString = [NSString stringWithFormat:@"%@collections/%@/items?key=%@&format=%@",urlString,collectionKey,oauthkey,format];
            }
            else{
                urlString = [NSString stringWithFormat:@"%@items/top?key=%@&format=%@",urlString,oauthkey,format];
            }
        }
        else if (type==ZPServerConnectionRequestItemsAndChildren){
            NSString* collectionKey = [parameters objectForKey:@"collectionKey"];
            NSAssert(collectionKey==NULL,@"Cannot request child items for collection");
            urlString = [NSString stringWithFormat:@"%@items?key=%@&format=atom",urlString,oauthkey];
        }

        else if( type == ZPServerConnectionRequestSingleItem){
             NSString* itemKey = [parameters objectForKey:@"itemKey"];

            urlString = [NSString stringWithFormat:@"%@items/%@?key=%@&format=atom",urlString,itemKey,oauthkey];
        }
        else if( type == ZPServerConnectionRequestSingleItemChildren){
            NSString* itemKey = [parameters objectForKey:@"itemKey"];
            
            urlString = [NSString stringWithFormat:@"%@items/%@/children?key=%@&format=atom",urlString,itemKey,oauthkey];
        }
        else if( type == ZPServerConnectionRequestKeys){
            urlString = [NSString stringWithFormat:@"%@items?key=%@&format=keys",urlString,oauthkey];
        }
                
        if(parameters!=NULL){
            for(id key in parameters){
                if(! [@"collectionKey" isEqualToString: key] &&
                   ! [@"libraryID" isEqualToString: key] &&
                   ! ((type == ZPServerConnectionRequestSingleItemChildren || type == ZPServerConnectionRequestSingleItem) && [@"itemKey" isEqualToString:key])) {
                    urlString = [NSString stringWithFormat:@"%@&%@=%@",urlString,key,[[parameters objectForKey:key] stringByAddingPercentEscapesUsingEncoding:
                                                                                      NSUTF8StringEncoding]];
                
                }
            }
        }
        
        responseData = [self _retrieveDataFromServer:urlString];
    }

    if(responseData!=NULL){

        ZPServerResponseXMLParser* parserDelegate = NULL;

        if(type == ZPServerConnectionRequestKeys || type == ZPServerConnectionRequestTopLevelKeys){
            //We do not use a parser for item keys because it is not XML. The itemkey format is kind of afterthough, so we will just parse it differentlys
            
            NSString* stringData = [[NSString alloc] initWithData:responseData
                                                     encoding:NSUTF8StringEncoding];
            parserDelegate = [[ZPServerResponseXMLParser alloc] init];
            NSMutableArray* itemKeys = [NSMutableArray arrayWithArray:[stringData componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
            
            //It is possible that we get empty keys at the end
            while([[itemKeys lastObject] isEqualToString:@""]) [itemKeys removeLastObject];

            [parserDelegate setParsedElements:itemKeys];
        }
        
        
        else{
            NSXMLParser* parser = [[NSXMLParser alloc] initWithData:responseData];

        //Choose the parser based on what we expect to receive
        
            if(type==ZPServerConnectionRequestGroups){
                parserDelegate =  [[ZPServerResponseXMLParserLibrary alloc] init];    
            }
            else if (type==ZPServerConnectionRequestCollections || type == ZPServerConnectionRequestSingleCollection){
                parserDelegate =  [[ZPServerResponseXMLParserCollection alloc] init];    
            }
            else if (type==ZPServerConnectionRequestItems || type == ZPServerConnectionRequestSingleItem || type== ZPServerConnectionRequestItemsAndChildren || type== ZPServerConnectionRequestSingleItemChildren){
                parserDelegate =  [[ZPServerResponseXMLParserItem alloc] init];    
            }
        
              
            [parser setDelegate: parserDelegate];
            [parser parse];
        }
        
        //Iy is OK to get 1/0 here because queries that return a single results do not have totalResults
        NSLog(@"Request returned %i/%i results: %@ Active queries: %i",[[parserDelegate parsedElements] count],[parserDelegate totalResults], urlString,_activeRequestCount);            
        
        //If there are no results, dump the entire response so that we see what the problem was
        if([[parserDelegate parsedElements] count] == 0){
            NSLog(@"%@",[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding]);
        }


        return parserDelegate;
    }
    else{
        if(oauthkey==NULL){

            //Initialize a new authentication process if there is currently not an ongoing one
            if(![[ZPAuthenticationProcess instance] isActive]){
                [[ZPAuthenticationProcess instance] startAuthentication];
            }
        }
        return NULL;
    }
}

-(ZPZoteroItem*) retrieveSingleItemDetailsFromServer:(ZPZoteroItem*)item{

    NSMutableDictionary* parameters = [NSMutableDictionary dictionaryWithObject:item.libraryID forKey:@"libraryID"];
    [parameters setObject:item.key forKey:@"itemKey"];
    [parameters setObject:@"json" forKey:@"content"];
    
    ZPServerResponseXMLParser* parserDelegate =  [self makeServerRequest:ZPServerConnectionRequestSingleItem withParameters:parameters];
    
    NSArray* parsedArray = [parserDelegate parsedElements];
    
    if(parserDelegate == NULL || [parsedArray count] == 0 ) return NULL;
    
    item = [parsedArray objectAtIndex:0];   

    //Request attachments for the single item

    if(item.numChildren >0){
        [parameters setObject:@"json" forKey:@"content"];
        parserDelegate =  [self makeServerRequest:ZPServerConnectionRequestSingleItemChildren withParameters:parameters];
        
        NSMutableArray* attachments = NULL;
        NSMutableArray* notes = NULL;
        
        for(NSObject* child in [parserDelegate parsedElements] ){
            if([child isKindOfClass:[ZPZoteroAttachment class]]){
                if(attachments == NULL) attachments = [NSMutableArray array];
               [attachments addObject:child];
            }
            else if([child isKindOfClass:[ZPZoteroNote class]]){
                if(notes == NULL) notes = [NSMutableArray array];
                [notes addObject:child];
            }
        }
        
        if(notes != NULL) item.notes = notes;
        else item.notes = [NSArray array];
        
        if(attachments != NULL) item.attachments = attachments;
        else item.attachments = [NSArray array];
    
    }
    return item;
}

-(NSArray*) retrieveLibrariesFromServer{
        
    //Retrieve all libraries from the server
    

    ZPServerResponseXMLParser* parserDelegate =  [self makeServerRequest:ZPServerConnectionRequestGroups withParameters:NULL];

    NSArray* returnArray = [parserDelegate parsedElements];
 
    if(parserDelegate == NULL) return NULL;
    
    //If there is more data coming, retrieve it
    while([returnArray count] < parserDelegate.totalResults){

        NSMutableDictionary* parameters=[[NSMutableDictionary alloc] initWithCapacity:1];
        [parameters setObject:[NSString stringWithFormat:@"%i",[returnArray count]] forKey:@"start"];

        ZPServerResponseXMLParser* parserDelegate =  [self makeServerRequest:ZPServerConnectionRequestGroups withParameters:parameters];

        if(parserDelegate == NULL) return NULL;
        
        NSArray* returnArray = [parserDelegate parsedElements];

        returnArray=[returnArray arrayByAddingObjectsFromArray:parserDelegate.parsedElements];
    }
    
    
    return returnArray;
    
}

-(NSArray*) retrieveCollectionsForLibraryFromServer:(NSNumber*)libraryID{
    
    NSMutableDictionary* parameters = [NSMutableDictionary dictionaryWithObject:libraryID forKey:@"libraryID"];

    ZPServerResponseXMLParser* parserDelegate =  [self makeServerRequest:ZPServerConnectionRequestCollections withParameters:parameters];
    if(parserDelegate == NULL) return NULL;

    NSArray* returnArray = [parserDelegate parsedElements];
    
    //If there is more data coming, retrieve it
    while([returnArray count] < parserDelegate.totalResults){
        
        [parameters setObject:[NSString stringWithFormat:@"%i",[returnArray count]] forKey:@"start"];
        
        ZPServerResponseXMLParser* parserDelegate =  [self makeServerRequest:ZPServerConnectionRequestCollections withParameters:parameters];
        if(parserDelegate == NULL) return NULL;
        
        returnArray=[returnArray arrayByAddingObjectsFromArray:parserDelegate.parsedElements];
    }
        
    return returnArray;
}

-(ZPZoteroCollection*) retrieveCollection:(NSString*)collectionKey fromLibrary:(NSNumber*)libraryID{

    NSMutableDictionary* parameters = [NSMutableDictionary dictionaryWithObject:libraryID forKey:@"libraryID"];
    [parameters setValue:collectionKey forKey:@"collectionKey"];
    
    ZPServerResponseXMLParser* parserDelegate =  [self makeServerRequest:ZPServerConnectionRequestSingleCollection withParameters:parameters];
    if(parserDelegate == NULL) return NULL;
    
    ZPZoteroCollection* collection= [[parserDelegate parsedElements] objectAtIndex:0];
    collection.libraryID = libraryID;
    
    return  collection;

}


-(NSArray*) retrieveItemsFromLibrary:(NSNumber*)libraryID itemKeys:(NSArray*)keys {
    
    
    NSMutableDictionary* parameters = [NSMutableDictionary dictionaryWithObject:libraryID  forKey:@"libraryID"];
    
    [parameters setObject:@"bib,json" forKey:@"content"];
    [parameters setObject:@"apa" forKey:@"style"];
    [parameters setObject:[keys componentsJoinedByString:@","] forKey:@"itemKey"];
        
    ZPServerResponseXMLParser* parserDelegate =  [self makeServerRequest:ZPServerConnectionRequestItemsAndChildren withParameters:parameters];
    
    return parserDelegate.parsedElements;
    
    
}
-(NSArray*) retrieveAllItemKeysFromLibrary:(NSNumber*)libraryID{
    
    NSMutableDictionary* parameters = [NSMutableDictionary dictionaryWithObject:libraryID  forKey:@"libraryID"];
    [parameters setObject:@"dateModified" forKey:@"order"];
    [parameters setObject:@"desc" forKey:@"sort"];
    ZPServerResponseXMLParser* parserDelegate =  [self makeServerRequest:ZPServerConnectionRequestKeys withParameters:parameters];
    
    return parserDelegate.parsedElements;
    
}
-(NSArray*) retrieveKeysInContainer:(NSNumber*)libraryID collectionKey:(NSString*)key{
    NSMutableDictionary* parameters = [NSMutableDictionary dictionaryWithObject:libraryID  forKey:@"libraryID"];
    if(key!=NULL) [parameters setValue:key forKey:@"collectionKey"];

    ZPServerResponseXMLParser* parserDelegate =  [self makeServerRequest:ZPServerConnectionRequestTopLevelKeys withParameters:parameters];
    
    return parserDelegate.parsedElements;
    
}

-(NSArray*) retrieveKeysInContainer:(NSNumber*)libraryID collectionKey:(NSString*)collectionKey searchString:(NSString*)searchString orderField:(NSString*)orderField sortDescending:(BOOL)sortDescending{
    
    NSMutableDictionary* parameters = [NSMutableDictionary dictionaryWithObject:libraryID  forKey:@"libraryID"];
    if(collectionKey!=NULL) [parameters setValue:collectionKey forKey:@"collectionKey"];
    
    //Search
    if(searchString!=NULL && ! [searchString isEqualToString:@""]){
        [parameters setObject:searchString forKey:@"q"];
    }
    //Sort
    if(orderField!=NULL){
        [parameters setObject:orderField forKey:@"order"];
        
        if(sortDescending){
            [parameters setObject:@"desc" forKey:@"sort"];
        }
        else{
            [parameters setObject:@"asc" forKey:@"sort"];
        }
    }
    //Get the most recent first by default
    else{
        [parameters setObject:@"dateModified" forKey:@"order"];
        [parameters setObject:@"desc" forKey:@"sort"];
    }
    
    ZPServerResponseXMLParser* parserDelegate =  [self makeServerRequest:ZPServerConnectionRequestTopLevelKeys withParameters:parameters];
    
    return parserDelegate.parsedElements;
    
}

-(NSString*) retrieveTimestampForContainer:(NSNumber*)libraryID collectionKey:(NSString*)key{
    
    NSMutableDictionary* parameters = [NSMutableDictionary dictionaryWithObject:libraryID  forKey:@"libraryID"];
    if(key!=NULL) [parameters setValue:key forKey:@"collectionKey"];
    
    
    [parameters setObject:@"none" forKey:@"content"];
    [parameters setObject:@"dateModified" forKey:@"order"];
    [parameters setObject:@"desc" forKey:@"sort"];
    [parameters setObject:@"0" forKey:@"start"];
    [parameters setObject:@"1" forKey:@"limit"];
    
    ZPServerResponseXMLParser* parserDelegate =  [self makeServerRequest:ZPServerConnectionRequestItems withParameters:parameters];
    
    return parserDelegate.updateTimestamp;
}


#pragma mark - Asynchronous file downloads

-(void) startDownloadingAttachment:(ZPZoteroAttachment*)attachment{
        
    _activeRequestCount++;

    //First request starts the network indicator
    if(_activeRequestCount==1) [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];

    //Use the first channel
    [[_fileChannels objectAtIndex:0] startDownloadingAttachment:attachment];

}
-(void) finishedDownloadingAttachment:(ZPZoteroAttachment*)attachment toFileAtPath:(NSString*) tempFile usingFileChannel:(ZPFileChannel*)fileChannel{

    _activeRequestCount--;
    
    if(tempFile == NULL){
        //No file file received, try the next channel 
        NSInteger index = [_fileChannels indexOfObject:fileChannel]+1;
        if(index < [_fileChannels count]){
            _activeRequestCount++;
            [[_fileChannels objectAtIndex:index] startDownloadingAttachment:attachment];
        }
        //In case of no more options to retry downloading, notify that downloading of this attachment has been finished.
        //It is up to the observers to determine if downloading was succesful
        else {
            [[ZPDataLayer instance] notifyAttachmentDownloadCompleted:attachment];
        }
    }
    else{
        //If we got a file, move it to the right place
        
        NSDictionary *_documentFileAttributes = [[NSFileManager defaultManager] fileAttributesAtPath:tempFile traverseLink:YES];
        
        if([_documentFileAttributes fileSize]>0){
            
            //Move the file to the right place
            NSString* targetPath = [attachment fileSystemPath];
            [[NSFileManager defaultManager] moveItemAtPath:tempFile toPath:targetPath error:NULL];
            
            //Set this file as not cached
            const char* filePath = [[attachment fileSystemPath] fileSystemRepresentation];
            const char* attrName = "com.apple.MobileBackup";
            u_int8_t attrValue = 1;
            setxattr(filePath, attrName, &attrValue, sizeof(attrValue), 0, 0);
            
            //We need to do this in a different thread so that the current thread does not count towards the operations count
            [[ZPDataLayer instance] performSelectorInBackground:@selector(notifyAttachmentDownloadCompleted:) withObject:attachment];

        }
        [[ZPDataLayer instance] notifyAttachmentDownloadCompleted:attachment];

    }
    
    //First request starts the network indicator
    if(_activeRequestCount==0) [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
    
}

-(void) cancelDownloadingAttachment:(ZPZoteroAttachment*)attachment{
    //Loop over the file channels and cancel downloading of this attachment
    for(ZPFileChannel* channnel in _fileChannels){
        [channnel cancelDownloadingAttachment:attachment];
    }
}

-(void) useProgressView:(UIProgressView*) progressView forAttachment:(ZPZoteroAttachment*)attachment{
    for(ZPFileChannel* channnel in _fileChannels){
        [channnel useProgressView:progressView forAttachment:attachment];
    }
}


@end
