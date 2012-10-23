//
//  ZPLogViewController.m
//  ZotPad
//
//  Created by Mikko Rönkkö on 30.6.2012.
//  Copyright (c) 2012 Mikko Rönkkö. All rights reserved.
//

#import "ZPCore.h"
#import "ZPLogViewController.h"
#import "ZPAppDelegate.h"
#import "DDFileLogger.h"
#import "ZPHelpPopover.h"
#import "UserVoice.h"
#import "UVSession.h"
#import "UVClientConfig.h"
#import <MessageUI/MessageUI.h>

@interface ZPLogViewController (){
    MFMailComposeViewController *mailController;
}

@end

@implementation ZPLogViewController

@synthesize logView,manualButton;

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
    
    ZPAppDelegate* appDelegate = (ZPAppDelegate*) [[UIApplication sharedApplication] delegate];
    NSString* logPath = [appDelegate.fileLogger.logFileManager.sortedLogFilePaths objectAtIndex:0];

    logView.text = [[NSString alloc] initWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:NULL];
//    [logView scrollRangeToVisible:NSMakeRange([logView.text length], 0)];
}
- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:YES];
    if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad){
        if([[NSUserDefaults standardUserDefaults] objectForKey:@"hasPresentedSecondaryHelpPopover"]==NULL){
            [ZPHelpPopover displayHelpPopoverFromToolbarButton:manualButton];
            [[NSUserDefaults standardUserDefaults] setObject:@"1" forKey:@"hasPresentedSecondaryHelpPopover"];
        }
    }

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

-(IBAction)showManual:(id)sender{
    QLPreviewController* ql = [[QLPreviewController alloc] init];
    ql.dataSource = self;
    [self presentModalViewController:ql animated:YES];
}

#if 0

-(IBAction)knowledgeBase:(id)sender{
    [[[UIAlertView alloc] initWithTitle:@"Not implemented"
                                message:@"Feedback and knowledge base are not available in beta builds."
                               delegate:nil
                      cancelButtonTitle:@"Cancel"
                      otherButtonTitles:nil]show];
}

#else

#import "ZPSecrets.h"

-(IBAction)contactSupport:(id)sender{
    UVConfig *config = [UVConfig configWithSite:@"zotpad.uservoice.com"
                                         andKey:USERVOICE_API_KEY
                                      andSecret:USERVOICE_SECRET];
    
    UIDevice *currentDevice = [UIDevice currentDevice];
    NSString *model = [currentDevice model];
    NSString *systemVersion = [currentDevice systemVersion];

    NSString* technicalInfo = [NSString stringWithFormat:@"\n\n --- Technical info ---\n\n%@ %@ (build %@)\n%@ (iOS %@)\nuserID: %@\nAPI key: %@\n\n --- Application log ----\n\n%@",
                               [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"],
                               [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                               [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"],
                               [[UIDevice currentDevice] model],
                               [[UIDevice currentDevice] systemVersion],
                               [ZPPreferences userID],
                               [ZPPreferences OAuthKey],
                               logView.text];

    config.customFields =  [NSDictionary dictionaryWithObject:technicalInfo
                                                       forKey:@"Technical Information"];
    
    [UserVoice presentUserVoiceContactUsFormForParentViewController:self andConfig:config];
}

#endif

-(IBAction)manageKey:(id)sender{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[@"https://www.zotero.org/settings/keys/edit/" stringByAppendingString:[ZPPreferences OAuthKey]]]];
}

-(IBAction)dismiss:(id)sender{
    [self dismissModalViewControllerAnimated:YES];
}

-(void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error {
    [mailController dismissModalViewControllerAnimated:YES];
    mailController = NULL;
}
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller{
    return 1;
}

- (id <QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index{
    NSString* manualType;
    if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad){
        manualType = @"UserManual"; 
    }
    else{
        manualType = @"iphone"; 
    }
    NSString *filePath = [[NSBundle mainBundle] pathForResource:manualType ofType:@"pdf"];  
    return [NSURL fileURLWithPath: filePath];
    
}
@end
