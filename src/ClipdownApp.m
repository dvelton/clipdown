#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <JavaScriptCore/JavaScriptCore.h>

static NSString * const ClipdownAutoPasteKey = @"autoPasteAfterConversion";
static NSString * const ClipdownIncludeSourceKey = @"includeSourceURL";

@interface ClipdownConverter : NSObject
- (instancetype)initWithScriptURL:(NSURL *)scriptURL;
- (NSString *)convertHTML:(NSString *)html sourceURL:(NSString *)sourceURL includeSourceURL:(BOOL)includeSourceURL error:(NSError **)error;
- (NSString *)convertPlainText:(NSString *)text error:(NSError **)error;
- (NSString *)markdownLinkWithTitle:(NSString *)title URL:(NSString *)url error:(NSError **)error;
- (NSString *)markdownImageWithAlt:(NSString *)alt URL:(NSString *)url error:(NSError **)error;
@end

@implementation ClipdownConverter {
    JSContext *_context;
}

- (instancetype)initWithScriptURL:(NSURL *)scriptURL {
    self = [super init];
    if (!self) return nil;

    _context = [[JSContext alloc] init];
    NSString *script = [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:nil];
    [_context evaluateScript:script ?: @""];
    return self;
}

- (NSString *)callFunction:(NSString *)function arguments:(NSArray *)arguments error:(NSError **)error {
    JSValue *fn = _context[function];
    if (!fn || fn.isUndefined) {
        if (error) {
            *error = [NSError errorWithDomain:@"Clipdown" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Converter script is missing a required function."}];
        }
        return nil;
    }

    JSValue *result = [fn callWithArguments:arguments];
    if (_context.exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"Clipdown" code:2 userInfo:@{NSLocalizedDescriptionKey: _context.exception.toString ?: @"Converter failed."}];
        }
        _context.exception = nil;
        return nil;
    }

    return result.toString;
}

- (NSString *)convertHTML:(NSString *)html sourceURL:(NSString *)sourceURL includeSourceURL:(BOOL)includeSourceURL error:(NSError **)error {
    return [self callFunction:@"convertHTML" arguments:@[html ?: @"", sourceURL ?: @"", @(includeSourceURL)] error:error];
}

- (NSString *)convertPlainText:(NSString *)text error:(NSError **)error {
    return [self callFunction:@"convertPlainText" arguments:@[text ?: @""] error:error];
}

- (NSString *)markdownLinkWithTitle:(NSString *)title URL:(NSString *)url error:(NSError **)error {
    return [self callFunction:@"markdownLink" arguments:@[title ?: url ?: @"", url ?: @""] error:error];
}

- (NSString *)markdownImageWithAlt:(NSString *)alt URL:(NSString *)url error:(NSError **)error {
    return [self callFunction:@"markdownImage" arguments:@[alt ?: @"", url ?: @""] error:error];
}

@end

@interface ClipdownAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation ClipdownAppDelegate {
    NSStatusItem *_statusItem;
    ClipdownConverter *_converter;
    EventHotKeyRef _hotKeyRef;
    EventHandlerRef _eventHandlerRef;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    NSURL *scriptURL = [[NSBundle mainBundle] URLForResource:@"clipdown-converter" withExtension:@"js"];
    if (!scriptURL) {
        NSString *executableDir = [NSBundle mainBundle].executableURL.URLByDeletingLastPathComponent.path;
        scriptURL = [NSURL fileURLWithPath:[executableDir stringByAppendingPathComponent:@"../Resources/clipdown-converter.js"]];
    }
    _converter = [[ClipdownConverter alloc] initWithScriptURL:scriptURL];

    [self configureMenuBar];
    [self registerHotKey];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    if (_hotKeyRef) UnregisterEventHotKey(_hotKeyRef);
    if (_eventHandlerRef) RemoveEventHandler(_eventHandlerRef);
}

- (BOOL)autoPasteAfterConversion {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:ClipdownAutoPasteKey];
    return value ? [value boolValue] : NO;
}

- (void)setAutoPasteAfterConversion:(BOOL)value {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:ClipdownAutoPasteKey];
}

- (BOOL)includeSourceURL {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:ClipdownIncludeSourceKey];
    return value ? [value boolValue] : NO;
}

- (void)setIncludeSourceURL:(BOOL)value {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:ClipdownIncludeSourceKey];
}

- (void)configureMenuBar {
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.title = @"Clipdown";
    _statusItem.button.toolTip = @"Paste clipboard content as clean Markdown";
    _statusItem.menu = [self makeMenu];
}

- (NSMenu *)makeMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Clipdown"];

    NSMenuItem *convertItem = [[NSMenuItem alloc] initWithTitle:@"Convert Clipboard to Markdown" action:@selector(convertClipboardOnly:) keyEquivalent:@""];
    convertItem.target = self;
    [menu addItem:convertItem];

    NSMenuItem *convertAndPasteItem = [[NSMenuItem alloc] initWithTitle:@"Convert and Paste" action:@selector(convertAndPaste:) keyEquivalent:@""];
    convertAndPasteItem.target = self;
    [menu addItem:convertAndPasteItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *autoPasteItem = [[NSMenuItem alloc] initWithTitle:@"Hotkey Converts and Pastes" action:@selector(toggleAutoPaste:) keyEquivalent:@""];
    autoPasteItem.target = self;
    autoPasteItem.state = self.autoPasteAfterConversion ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:autoPasteItem];

    NSMenuItem *includeSourceItem = [[NSMenuItem alloc] initWithTitle:@"Include Source URL When Available" action:@selector(toggleIncludeSource:) keyEquivalent:@""];
    includeSourceItem.target = self;
    includeSourceItem.state = self.includeSourceURL ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:includeSourceItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *hotkeyItem = [[NSMenuItem alloc] initWithTitle:@"Hotkey: Control-Option-Command-V" action:nil keyEquivalent:@""];
    hotkeyItem.enabled = NO;
    [menu addItem:hotkeyItem];

    NSMenuItem *permissionsItem = [[NSMenuItem alloc] initWithTitle:@"Open Accessibility Settings" action:@selector(openAccessibilitySettings:) keyEquivalent:@""];
    permissionsItem.target = self;
    [menu addItem:permissionsItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit Clipdown" action:@selector(terminate:) keyEquivalent:@"q"];
    [menu addItem:quitItem];

    return menu;
}

- (void)registerHotKey {
    EventTypeSpec eventType = { kEventClassKeyboard, kEventHotKeyPressed };
    OSStatus handlerStatus = InstallEventHandler(GetApplicationEventTarget(), HotKeyHandler, 1, &eventType, (__bridge void *)self, &_eventHandlerRef);

    EventHotKeyID hotKeyID;
    hotKeyID.signature = 'CLPD';
    hotKeyID.id = 1;

    OSStatus hotKeyStatus = RegisterEventHotKey(kVK_ANSI_V, cmdKey | optionKey | controlKey, hotKeyID, GetApplicationEventTarget(), 0, &_hotKeyRef);

    if (handlerStatus != noErr || hotKeyStatus != noErr) {
        NSLog(@"Clipdown hotkey registration failed. handlerStatus=%d hotKeyStatus=%d", handlerStatus, hotKeyStatus);
        [self notifyWithTitle:@"Clipdown hotkey unavailable" message:@"Another app may already be using Control-Option-Command-V."];
    }
}

static OSStatus HotKeyHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    EventHotKeyID hotKeyID;
    GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hotKeyID), NULL, &hotKeyID);
    if (hotKeyID.signature == 'CLPD' && hotKeyID.id == 1) {
        ClipdownAppDelegate *delegate = (__bridge ClipdownAppDelegate *)userData;
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate convertClipboardAndPasteIfNeeded:delegate.autoPasteAfterConversion];
        });
    }
    return noErr;
}

- (void)convertClipboardOnly:(id)sender {
    [self convertClipboardAndPasteIfNeeded:NO];
}

- (void)convertAndPaste:(id)sender {
    [self convertClipboardAndPasteIfNeeded:YES];
}

- (void)toggleAutoPaste:(NSMenuItem *)sender {
    self.autoPasteAfterConversion = !self.autoPasteAfterConversion;
    sender.state = self.autoPasteAfterConversion ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)toggleIncludeSource:(NSMenuItem *)sender {
    self.includeSourceURL = !self.includeSourceURL;
    sender.state = self.includeSourceURL ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)openAccessibilitySettings:(id)sender {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)convertClipboardAndPasteIfNeeded:(BOOL)pasteAfterConversion {
    NSError *error = nil;
    NSString *sourceDescription = nil;
    NSString *markdown = [self markdownFromPasteboard:[NSPasteboard generalPasteboard] sourceDescription:&sourceDescription error:&error];

    if (!markdown.length) {
        [self notifyWithTitle:@"Clipdown could not convert this clipboard" message:error.localizedDescription ?: @"No convertible clipboard content found."];
        return;
    }

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:markdown forType:NSPasteboardTypeString];
    [self notifyWithTitle:@"Converted to Markdown" message:[NSString stringWithFormat:@"Converted %@.", sourceDescription ?: @"clipboard content"]];

    if (pasteAfterConversion) {
        [self pasteFrontmostApp];
    }
}

- (NSString *)markdownFromPasteboard:(NSPasteboard *)pasteboard sourceDescription:(NSString **)sourceDescription error:(NSError **)error {
    NSString *sourceURL = [self sourceURLFromPasteboard:pasteboard];

    NSString *html = [pasteboard stringForType:NSPasteboardTypeHTML];
    if (html.length) {
        if (sourceDescription) *sourceDescription = @"HTML";
        return [_converter convertHTML:html sourceURL:sourceURL includeSourceURL:self.includeSourceURL error:error];
    }

    NSData *rtf = [pasteboard dataForType:NSPasteboardTypeRTF];
    if (rtf.length) {
        NSString *converted = [self markdownFromAttributedData:rtf documentType:NSRTFTextDocumentType error:error];
        if (converted.length) {
            if (sourceDescription) *sourceDescription = @"rich text";
            return converted;
        }
    }

    NSData *rtfd = [pasteboard dataForType:NSPasteboardTypeRTFD];
    if (rtfd.length) {
        NSString *converted = [self markdownFromAttributedData:rtfd documentType:NSRTFDTextDocumentType error:error];
        if (converted.length) {
            if (sourceDescription) *sourceDescription = @"rich text";
            return converted;
        }
    }

    NSArray<NSURL *> *fileURLs = [pasteboard readObjectsForClasses:@[[NSURL class]] options:nil];
    NSMutableArray<NSString *> *fileMarkdown = [NSMutableArray array];
    for (NSURL *url in fileURLs) {
        if (url.isFileURL) {
            NSString *convertedFile = [self markdownForFileURL:url error:error];
            if (convertedFile.length) {
                [fileMarkdown addObject:convertedFile];
            }
        }
    }
    if (fileMarkdown.count) {
        if (sourceDescription) *sourceDescription = fileMarkdown.count == 1 ? @"file" : @"files";
        return [fileMarkdown componentsJoinedByString:@"\n"];
    }

    NSString *urlString = [self URLStringFromPasteboard:pasteboard];
    if (urlString.length) {
        NSString *title = [pasteboard stringForType:@"public.url-name"] ?: urlString;
        if (sourceDescription) *sourceDescription = @"URL";
        return [_converter markdownLinkWithTitle:title URL:urlString error:error];
    }

    NSString *text = [pasteboard stringForType:NSPasteboardTypeString];
    if (text.length) {
        if (sourceDescription) *sourceDescription = @"plain text";
        return [_converter convertPlainText:text error:error];
    }

    if (error) {
        *error = [NSError errorWithDomain:@"Clipdown" code:3 userInfo:@{NSLocalizedDescriptionKey: @"The clipboard does not contain text, HTML, rich text, a URL, or files."}];
    }
    return nil;
}

- (NSString *)markdownFromAttributedData:(NSData *)data documentType:(NSAttributedStringDocumentType)documentType error:(NSError **)error {
    NSAttributedString *attributed = [[NSAttributedString alloc] initWithData:data options:@{NSDocumentTypeDocumentAttribute: documentType} documentAttributes:nil error:error];
    if (!attributed.length) return nil;

    NSData *htmlData = [attributed dataFromRange:NSMakeRange(0, attributed.length) documentAttributes:@{NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType} error:error];
    NSString *html = [[NSString alloc] initWithData:htmlData encoding:NSUTF8StringEncoding];
    if (html.length) {
        return [_converter convertHTML:html sourceURL:nil includeSourceURL:NO error:error];
    }

    return [_converter convertPlainText:attributed.string error:error];
}

- (NSString *)sourceURLFromPasteboard:(NSPasteboard *)pasteboard {
    NSString *urlString = [self URLStringFromPasteboard:pasteboard];
    if ([urlString hasPrefix:@"http://"] || [urlString hasPrefix:@"https://"]) {
        return urlString;
    }
    return nil;
}

- (NSString *)URLStringFromPasteboard:(NSPasteboard *)pasteboard {
    NSString *urlString = [pasteboard stringForType:NSPasteboardTypeURL] ?: [pasteboard stringForType:@"public.url"];
    if (urlString.length) return urlString;

    NSString *text = [[pasteboard stringForType:NSPasteboardTypeString] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([text rangeOfString:@"^(https?|file)://\\S+$" options:NSRegularExpressionSearch].location != NSNotFound) {
        return text;
    }
    return nil;
}

- (NSString *)markdownForFileURL:(NSURL *)url error:(NSError **)error {
    NSString *filename = url.lastPathComponent.length ? url.lastPathComponent : url.absoluteString;
    NSSet<NSString *> *imageExtensions = [NSSet setWithArray:@[@"png", @"jpg", @"jpeg", @"gif", @"webp", @"tiff", @"bmp", @"heic"]];
    if ([imageExtensions containsObject:url.pathExtension.lowercaseString]) {
        return [_converter markdownImageWithAlt:filename URL:url.absoluteString error:error];
    }
    return [_converter markdownLinkWithTitle:filename URL:url.absoluteString error:error];
}

- (void)pasteFrontmostApp {
    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) {
        [self notifyWithTitle:@"Clipdown needs Accessibility permission" message:@"Allow Clipdown in Accessibility settings to paste automatically."];
        [self openAccessibilitySettings:nil];
        return;
    }

    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
    CGEventRef keyDown = CGEventCreateKeyboardEvent(source, kVK_ANSI_V, true);
    CGEventRef keyUp = CGEventCreateKeyboardEvent(source, kVK_ANSI_V, false);
    CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
    CGEventSetFlags(keyUp, kCGEventFlagMaskCommand);
    CGEventPost(kCGHIDEventTap, keyDown);
    CGEventPost(kCGHIDEventTap, keyUp);
    if (keyDown) CFRelease(keyDown);
    if (keyUp) CFRelease(keyUp);
    if (source) CFRelease(source);
}

- (void)notifyWithTitle:(NSString *)title message:(NSString *)message {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSUserNotification *notification = [[NSUserNotification alloc] init];
    notification.title = title;
    notification.informativeText = message;
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
#pragma clang diagnostic pop
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        ClipdownAppDelegate *delegate = [[ClipdownAppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
