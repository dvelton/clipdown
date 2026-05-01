#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

static void Expect(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static NSString *Call(JSContext *context, NSString *function, NSArray *arguments) {
    JSValue *result = [context[function] callWithArguments:arguments];
    if (context.exception) {
        NSLog(@"JS exception: %@", context.exception);
        exit(1);
    }
    return result.toString;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            NSLog(@"Usage: ClipdownConverterTests /path/to/clipdown-converter.js");
            return 2;
        }

        NSURL *scriptURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSString *script = [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:nil];
        Expect(script.length > 0, @"Could not load converter script.");

        JSContext *context = [[JSContext alloc] init];
        [context evaluateScript:script];
        if (context.exception) {
            NSLog(@"JS exception while loading script: %@", context.exception);
            return 1;
        }

        NSString *html = @"<article><h1>Release notes</h1><p>Hello <strong>team</strong>, read <a href=\"https://example.com\">the update</a>.</p><ul><li>Fast</li><li>Local</li></ul></article>";
        NSString *markdown = Call(context, @"convertHTML", @[html, @"", @NO]);
        Expect([markdown containsString:@"# Release notes"], @"Expected heading conversion.");
        Expect([markdown containsString:@"Hello **team**, read [the update](https://example.com)."], @"Expected inline formatting conversion.");
        Expect([markdown containsString:@"- Fast"], @"Expected first list item.");
        Expect([markdown containsString:@"- Local"], @"Expected second list item.");

        NSString *tableHTML = @"<table><tr><th>Name</th><th>Status</th></tr><tr><td>Clipdown</td><td>Local</td></tr></table>";
        NSString *tableMarkdown = Call(context, @"convertHTML", @[tableHTML, @"", @NO]);
        Expect([tableMarkdown isEqualToString:@"| Name | Status |\n| --- | --- |\n| Clipdown | Local |"], [NSString stringWithFormat:@"Expected table conversion, got:\n%@", tableMarkdown]);

        NSString *codeMarkdown = Call(context, @"convertHTML", @[@"<pre><code>let value = 1\nprint(value)</code></pre>", @"", @NO]);
        Expect([codeMarkdown containsString:@"```"], @"Expected fenced code block.");
        Expect([codeMarkdown containsString:@"let value = 1"], @"Expected first code line.");
        Expect([codeMarkdown containsString:@"print(value)"], @"Expected second code line.");

        NSString *tsvMarkdown = Call(context, @"convertPlainText", @[@"Name\tStatus\nClipdown\tLocal"]);
        Expect([tsvMarkdown isEqualToString:@"| Name | Status |\n| --- | --- |\n| Clipdown | Local |"], @"Expected TSV table conversion.");

        NSString *urlMarkdown = Call(context, @"convertPlainText", @[@"https://github.com/dvelton"]);
        Expect([urlMarkdown isEqualToString:@"[https://github.com/dvelton](https://github.com/dvelton)"], @"Expected URL conversion.");

        NSString *parenURLMarkdown = Call(context, @"markdownLink", @[@"Example", @"https://example.com/a path/file_(1).html"]);
        Expect([parenURLMarkdown isEqualToString:@"[Example](https://example.com/a%20path/file_%281%29.html)"], @"Expected safe Markdown URL escaping.");

        NSString *invalidEntityMarkdown = Call(context, @"convertHTML", @[@"<p>Bad entity: &#999999999;</p>", @"", @NO]);
        Expect([invalidEntityMarkdown containsString:@"Bad entity:"], @"Expected invalid numeric HTML entities not to abort conversion.");

        NSString *scriptMarkdown = Call(context, @"convertHTML", @[@"<script>if (a < b) {}</script><p>Visible</p>", @"", @NO]);
        Expect([scriptMarkdown isEqualToString:@"Visible"], @"Expected script contents to be skipped without swallowing visible HTML.");

        NSString *proseMarkdown = Call(context, @"convertPlainText", @[@"Hello, world\nGoodbye, world"]);
        Expect([proseMarkdown isEqualToString:@"Hello, world\nGoodbye, world"], @"Expected comma prose not to be treated as CSV.");

        NSString *quotedCSVMarkdown = Call(context, @"convertPlainText", @[@"\"Name\",\"Status\"\n\"Clipdown\",\"Local\""]);
        Expect([quotedCSVMarkdown isEqualToString:@"| Name | Status |\n| --- | --- |\n| Clipdown | Local |"], @"Expected quoted CSV table conversion.");

        NSString *plainMarkdown = Call(context, @"convertPlainText", @[@"Hello,\n\nworld."]);
        Expect([plainMarkdown isEqualToString:@"Hello,\n\nworld."], @"Expected plain text preservation.");

        NSLog(@"All Clipdown converter tests passed.");
    }
    return 0;
}
