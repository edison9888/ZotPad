//
//  ZPUploadVersionConflictViewControllerViewController.m
//  ZotPad
//
//  Created by Mikko Rönkkö on 27.6.2012.
//  Copyright (c) 2012 Helsiki University of Technology. All rights reserved.
//

#import "ZPUploadVersionConflictViewControllerViewController.h"
#import "ZPDatabase.h"
#import "ZPAttachmentIconViewController.h"

// A helper class for showing an original version of the attachment


@interface ZPUploadVersionConflictViewControllerViewController ()

@end

@implementation ZPUploadVersionConflictViewControllerViewController

@synthesize attachment, label, carousel, fileChannel,secondaryCarousel;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.

    _carouselDelegate = [[ZPAttachmentCarouselDelegate alloc] init];
    
    //iPhone shows the versions in carousel. On iPad they are shown in separate carousels
    
    if(secondaryCarousel==NULL){
        [_carouselDelegate configureWithAttachmentArray:[NSArray arrayWithObjects:attachment, attachment, nil]];
        _carouselDelegate.mode = ZPATTACHMENTICONGVIEWCONTROLLER_MODE_FIRST_STATIC_SECOND_DOWNLOAD;
        _carouselDelegate.show = ZPATTACHMENTICONGVIEWCONTROLLER_SHOW_FIRST_MODIFIED_SECOND_ORIGINAL;
        carousel.type = iCarouselTypeCoverFlow2;
    }
    else{
        [_carouselDelegate configureWithAttachmentArray:[NSArray arrayWithObject:attachment]];
        _carouselDelegate.mode = ZPATTACHMENTICONGVIEWCONTROLLER_MODE_STATIC;
        _carouselDelegate.show = ZPATTACHMENTICONGVIEWCONTROLLER_SHOW_MODIFIED;
    }
    _carouselDelegate.attachmentCarousel = carousel;
    carousel.delegate = _carouselDelegate;
    carousel.dataSource = _carouselDelegate;

    carousel.currentItemIndex = 0;

    
    if(secondaryCarousel!=NULL){
        _secondaryCarouselDelegate = [[ZPAttachmentCarouselDelegate alloc] init];
        _secondaryCarouselDelegate.mode = ZPATTACHMENTICONGVIEWCONTROLLER_MODE_DOWNLOAD;
        _secondaryCarouselDelegate.show = ZPATTACHMENTICONGVIEWCONTROLLER_SHOW_ORIGINAL;
        [_secondaryCarouselDelegate configureWithAttachmentArray:[NSArray arrayWithObject: attachment]];
        _secondaryCarouselDelegate.attachmentCarousel = secondaryCarousel;
        secondaryCarousel.delegate = _secondaryCarouselDelegate;
        secondaryCarousel.dataSource = _secondaryCarouselDelegate;
        secondaryCarousel.currentItemIndex = 0;
    }


    label.text = [NSString stringWithFormat:@"File '%@' has changed on server",attachment.filename];

}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}

#pragma mark - Actions

-(IBAction)useMyVersion:(id)sender{
    [[ZPDatabase instance] writeVersionInfoForAttachment:attachment];
    [fileChannel startUploadingAttachment:attachment];
    [self dismissModalViewControllerAnimated:YES];
    [[ZPDataLayer instance] notifyAttachmentUploadStarted:attachment];
}
-(IBAction)useRemoteVersion:(id)sender{
    attachment.versionIdentifier_local = [NSNull null];
    [attachment purge_modified:@"User chose server file during conflict"];
    [[ZPDatabase instance] writeVersionInfoForAttachment:attachment];
    [fileChannel cancelUploadingAttachment:attachment];
    [self dismissModalViewControllerAnimated:YES];
    [[ZPDataLayer instance] notifyAttachmentUploadCanceled:attachment];    
}


@end
