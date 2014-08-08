//
//  MMPaperState.m
//  LooseLeaf
//
//  Created by Adam Wulf on 9/24/13.
//  Copyright (c) 2013 Milestone Made, LLC. All rights reserved.
//

#import "JotViewStateProxy.h"
#import <JotUI/JotUI.h>
#import "JotViewState.h"

static dispatch_queue_t loadUnloadStateQueue;

@implementation JotViewStateProxy{
    // ideal state
    BOOL shouldKeepStateLoaded;
    BOOL isLoadingState;
    
    NSUInteger lastSavedUndoHash;
    JotViewState* jotViewState;
}

+(dispatch_queue_t) loadUnloadStateQueue{
    if(!loadUnloadStateQueue){
        loadUnloadStateQueue = dispatch_queue_create("com.milestonemade.looseleaf.loadUnloadStateQueue", DISPATCH_QUEUE_SERIAL);
    }
    return loadUnloadStateQueue;
}

@synthesize delegate;
@synthesize jotViewState;

-(id) initWithDelegate:(NSObject<JotViewStateProxyDelegate> *)_delegate{
    if(self = [super init]){
        self.delegate = _delegate;
    }
    return self;
}

-(int) fullByteSize{
    return jotViewState.fullByteSize;
}

-(void) loadStateAsynchronously:(BOOL)async withSize:(CGSize)pagePixelSize andContext:(JotGLContext*)context andBufferManager:(JotBufferManager*)bufferManager{
    @synchronized(self){
        // if we're already loading our
        // state, then bail early
        if(isLoadingState){
            return;
        }
        // if we already have our state,
        // then bail early
        if(jotViewState){
            return;
        }
        
        shouldKeepStateLoaded = YES;
        isLoadingState = YES;
    }

    void (^block2)() = ^(void) {
        @autoreleasepool {
            BOOL shouldLoadState = NO;
            @synchronized(self){
                shouldLoadState = !jotViewState && shouldKeepStateLoaded;
            }
            
            if(shouldLoadState){
                if(!shouldKeepStateLoaded){
                    NSLog(@"will waste some time loading a JotViewState that we don't need...");
                }
                jotViewState = [[JotViewState alloc] initWithImageFile:delegate.jotViewStateInkPath
                                                          andStateFile:delegate.jotViewStatePlistPath
                                                           andPageSize:pagePixelSize
                                                          andGLContext:context
                                                      andBufferManager:bufferManager];
                if(!shouldKeepStateLoaded){
                    NSLog(@"wasted some time loading a JotViewState that we didn't need...");
                }
                BOOL shouldNotify = NO;
                @synchronized(self){
                    if(shouldKeepStateLoaded){
                        lastSavedUndoHash = [jotViewState undoHash];
                        shouldNotify = YES;
                    }else{
                        shouldNotify = NO;
                        // when loading state, we were actually
                        // told that we didn't really need the
                        // state after all, so just throw it away :(
                    }
                }
                if(shouldNotify){
                    // nothing changed in our goals since we started
                    // to load state, so notify our delegate
                    [self.delegate didLoadState:self];
                }else{
                    [[JotTrashManager sharedInstance] addObjectToDealloc:jotViewState];
                    @synchronized(self){
                        jotViewState = nil;
                        lastSavedUndoHash = 0;
                    }
                }
                @synchronized(self){
                    isLoadingState = NO;
                }
            }else if(!shouldKeepStateLoaded){
                @synchronized(self){
//                    NSLog(@"saved an excess load");
                    isLoadingState = NO;
                }
            }else{
                @synchronized(self){
                    isLoadingState = NO;
                }
            }
        }
    };
    
    if(async){
        dispatch_async(([JotViewStateProxy loadUnloadStateQueue]), block2);
    }else{
        block2();
    }
}

-(void) wasSavedAtImmutableState:(JotViewImmutableState*)immutableState{
    lastSavedUndoHash = [immutableState undoHash];
}

-(void) unload{
    JotViewStateProxy* strongSelf = self;
    @synchronized(self){
        shouldKeepStateLoaded = NO;
        if([self isStateLoaded] && !isLoadingState){
            dispatch_async(([JotViewStateProxy loadUnloadStateQueue]), ^{
                @autoreleasepool {
                    @synchronized(strongSelf){
                        if([self isStateLoaded]){
                            shouldKeepStateLoaded = NO;
                            if(isLoadingState){
                                // hrm, need to unload the state that
                                // never loaded in the first place.
                                // tell the state to immediately unload
                                // after it finishes
                                shouldKeepStateLoaded = NO;
                            }else if([strongSelf hasEditsToSave]){
                                NSLog(@"what?? %lu %lu", (unsigned long)[strongSelf.jotViewState undoHash], (unsigned long)[strongSelf lastSavedUndoHash]);
                                @throw [NSException exceptionWithName:@"UnloadedEditedPageException" reason:@"The page has been asked to unload, but has edits pending save" userInfo:nil];
                            }
                            if(!isLoadingState && jotViewState){
                                [[JotTrashManager sharedInstance] addObjectToDealloc:jotViewState];
                                jotViewState = nil;
                                [strongSelf.delegate didUnloadState:strongSelf];
                            }
                        }else{
                            NSLog(@"unloading a state proxy that's already unloaded");
                        }
                    }
                }
            });
        }else{
//            NSLog(@"saved an extra unload");
        }
    }
}

-(BOOL) isStateLoaded{
    return jotViewState != nil;
}

-(BOOL) isReadyToExport{
    return [jotViewState isReadyToExport];
}

-(JotGLTexture*) backgroundTexture{
    return [jotViewState backgroundTexture];
}

-(NSArray*) everyVisibleStroke{
    return [jotViewState everyVisibleStroke];
}

-(void) tick{
    return [jotViewState tick];
}

-(NSMutableArray*) strokesBeingWrittenToBackingTexture{
    return [jotViewState strokesBeingWrittenToBackingTexture];
}

-(JotViewImmutableState*) immutableState{
    return [jotViewState immutableState];
}

-(JotBufferManager*) bufferManager{
    return [jotViewState bufferManager];
}

-(JotStroke*) currentStroke{
    return [jotViewState currentStroke];
}
-(void) setCurrentStroke:(JotStroke *)currentStroke{
    [jotViewState setCurrentStroke:currentStroke];
}

-(NSMutableArray*) stackOfStrokes{
    return [jotViewState stackOfStrokes];
}
-(NSMutableArray*) stackOfUndoneStrokes{
    return [jotViewState stackOfUndoneStrokes];
}

-(JotGLTextureBackedFrameBuffer*) backgroundFramebuffer{
    return [jotViewState backgroundFramebuffer];
}

-(NSUInteger) undoHash{
    return [jotViewState undoHash];
}

/**
 * we have more information to save, if our
 * drawable view's hash does not equal to our
 * currently saved hash
 */
-(BOOL) hasEditsToSave{
    return [self.jotViewState undoHash] != lastSavedUndoHash;
}

-(NSUInteger) currentStateUndoHash{
    return [self.jotViewState undoHash];
}
-(NSUInteger) lastSavedUndoHash{
    return lastSavedUndoHash;
}



-(void) dealloc{
    if([self hasEditsToSave]){
        NSLog(@"oh no %d", [self hasEditsToSave]);
    }
}

@end
