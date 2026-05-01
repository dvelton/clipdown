function cleanMarkdown(value) {
  return String(value || "")
    .replace(/\r\n?/g, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function collapseWhitespace(value) {
  return String(value || "").replace(/\s+/g, " ").trim();
}

function escapeInline(value) {
  return String(value || "")
    .replace(/\\/g, "\\\\")
    .replace(/`/g, "\\`")
    .replace(/\*/g, "\\*")
    .replace(/_/g, "\\_")
    .replace(/\[/g, "\\[")
    .replace(/\]/g, "\\]");
}

function escapeTableCell(value) {
  return cleanMarkdown(value)
    .replace(/\n/g, "<br>")
    .replace(/\|/g, "\\|");
}

function markdownLink(title, url) {
  var safeTitle = escapeInline(title || url);
  var safeURL = markdownDestination(url);
  return "[" + safeTitle + "](" + safeURL + ")";
}

function markdownImage(alt, url) {
  var safeAlt = escapeInline(alt || "");
  var safeURL = markdownDestination(url);
  return "![" + safeAlt + "](" + safeURL + ")";
}

function markdownDestination(url) {
  var value = String(url || "").trim();
  try {
    value = encodeURI(value);
  } catch (error) {
    value = value.replace(/[\u0000-\u001F\u007F\s]/g, "");
  }
  return value
    .replace(/\(/g, "%28")
    .replace(/\)/g, "%29")
    .replace(/</g, "%3C")
    .replace(/>/g, "%3E")
    .replace(/\\/g, "%5C");
}

function sanitizedSourceURL(url) {
  return String(url || "").trim().replace(/[?#].*$/, "");
}

function looksLikeURL(value) {
  return /^(https?|file):\/\/\S+$/i.test(String(value || "").trim());
}

function headingPrefix(level) {
  return "#".repeat(Math.max(1, Math.min(level || 1, 6)));
}

function codeFence(value) {
  var longest = 0;
  var matches = String(value || "").match(/`+/g) || [];
  for (var i = 0; i < matches.length; i++) {
    longest = Math.max(longest, matches[i].length);
  }
  return "`".repeat(Math.max(3, longest + 1));
}

function renderTable(rows) {
  if (!rows.length) return "";
  var width = rows.reduce(function(max, row) { return Math.max(max, row.length); }, 0);
  var normalized = rows.map(function(row) {
    var copy = row.slice(0, width);
    while (copy.length < width) copy.push("");
    return copy;
  });
  var lines = [];
  lines.push("| " + normalized[0].map(escapeTableCell).join(" | ") + " |");
  lines.push("| " + normalized[0].map(function() { return "---"; }).join(" | ") + " |");
  for (var i = 1; i < normalized.length; i++) {
    lines.push("| " + normalized[i].map(escapeTableCell).join(" | ") + " |");
  }
  return lines.join("\n");
}

function parseDelimitedRow(row, delimiter) {
  if (delimiter !== ",") {
    return row.split(delimiter).map(function(cell) { return cell.trim(); });
  }

  var cells = [];
  var current = "";
  var inQuotes = false;
  for (var i = 0; i < row.length; i++) {
    var ch = row[i];
    if (ch === '"') {
      if (inQuotes && row[i + 1] === '"') {
        current += '"';
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch === delimiter && !inQuotes) {
      cells.push(current.trim());
      current = "";
    } else {
      current += ch;
    }
  }
  cells.push(current.trim());
  return cells;
}

function tableFromText(text) {
  var rows = String(text || "").replace(/\r\n?/g, "\n").split("\n").filter(function(row) {
    return row.trim().length > 0;
  });
  if (rows.length < 2) return null;

  var delimiter = null;
  if (rows.every(function(row) { return row.indexOf("\t") !== -1; })) {
    delimiter = "\t";
  } else if (rows.every(function(row) { return row.indexOf(",") !== -1; }) && rows.some(function(row) { return row.indexOf('"') !== -1; })) {
    delimiter = ",";
  } else {
    return null;
  }

  var parsed = rows.map(function(row) { return parseDelimitedRow(row, delimiter); });
  var width = parsed[0].length;
  if (width < 2 || !parsed.every(function(row) { return row.length === width; })) {
    return null;
  }

  return renderTable(parsed);
}

function convertPlainText(text) {
  var table = tableFromText(text);
  if (table) return table;

  var trimmed = String(text || "").trim();
  if (looksLikeURL(trimmed)) {
    return markdownLink(trimmed, trimmed);
  }

  return cleanMarkdown(text);
}

function decodeHTML(value) {
  var named = {
    amp: "&",
    lt: "<",
    gt: ">",
    quot: "\"",
    apos: "'",
    nbsp: " ",
    mdash: "--",
    ndash: "-",
    hellip: "...",
    copy: "(c)",
    reg: "(r)",
    trade: "(tm)"
  };

  return String(value || "").replace(/&(#x?[0-9a-fA-F]+|[A-Za-z]+);/g, function(match, entity) {
    var lower = entity.toLowerCase();
    if (Object.prototype.hasOwnProperty.call(named, lower)) return named[lower];
    if (lower[0] === "#") {
      var base = lower[1] === "x" ? 16 : 10;
      var digits = base === 16 ? lower.slice(2) : lower.slice(1);
      var scalar = parseInt(digits, base);
      if (!isNaN(scalar) && scalar >= 0 && scalar <= 0x10FFFF && !(scalar >= 0xD800 && scalar <= 0xDFFF)) {
        return String.fromCodePoint(scalar);
      }
    }
    return match;
  });
}

function node(tag, attrs, children, text) {
  return {
    tag: tag || null,
    attrs: attrs || {},
    children: children || [],
    text: text == null ? null : String(text)
  };
}

function parseAttrs(raw) {
  var attrs = {};
  var regex = /([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'>/]+))/g;
  var match;
  while ((match = regex.exec(raw)) !== null) {
    attrs[match[1].toLowerCase()] = decodeHTML(match[3] || match[4] || match[5] || "");
  }
  return attrs;
}

function parseStartTag(raw) {
  var content = raw.trim();
  if (!content || content[0] === "/") return null;
  var selfClosing = /\/\s*$/.test(content);
  content = content.replace(/\/\s*$/, "").trim();
  var nameMatch = content.match(/^([^\s/]+)/);
  if (!nameMatch) return null;
  var name = nameMatch[1].toLowerCase();
  var attrString = content.slice(nameMatch[0].length);
  return { name: name, attrs: parseAttrs(attrString), selfClosing: selfClosing };
}

function parseHTML(html) {
  var voidTags = {
    area: true, base: true, br: true, col: true, embed: true, hr: true,
    img: true, input: true, link: true, meta: true, param: true, source: true,
    track: true, wbr: true
  };
  var root = node(null, {}, []);
  var stack = [root];
  var i = 0;
  var source = String(html || "");

  while (i < source.length) {
    if (source[i] === "<") {
      if (source.slice(i, i + 4) === "<!--") {
        var commentEnd = source.indexOf("-->", i + 4);
        i = commentEnd === -1 ? source.length : commentEnd + 3;
        continue;
      }

      if (source.slice(i, i + 2) === "</") {
        var closeEnd = source.indexOf(">", i + 2);
        if (closeEnd === -1) break;
        var closeName = source.slice(i + 2, closeEnd).trim().split(/\s+/)[0].toLowerCase();
        while (stack.length > 1) {
          var removed = stack.pop();
          if (removed.tag === closeName) break;
        }
        i = closeEnd + 1;
        continue;
      }

      if (source.slice(i, i + 2) === "<!" || source.slice(i, i + 2) === "<?") {
        var declarationEnd = source.indexOf(">", i + 2);
        i = declarationEnd === -1 ? source.length : declarationEnd + 1;
        continue;
      }

      var quote = null;
      var j = i + 1;
      for (; j < source.length; j++) {
        var c = source[j];
        if (quote) {
          if (c === quote) quote = null;
        } else if (c === '"' || c === "'") {
          quote = c;
        } else if (c === ">") {
          break;
        }
      }

      if (j >= source.length) break;
      var tag = parseStartTag(source.slice(i + 1, j));
      if (tag) {
        var child = node(tag.name, tag.attrs, []);
        stack[stack.length - 1].children.push(child);
        if (tag.name === "script" || tag.name === "style") {
          var lowerSource = source.toLowerCase();
          var closeNeedle = "</" + tag.name;
          var rawClose = lowerSource.indexOf(closeNeedle, j + 1);
          if (rawClose === -1) {
            i = source.length;
          } else {
            var rawCloseEnd = source.indexOf(">", rawClose);
            i = rawCloseEnd === -1 ? source.length : rawCloseEnd + 1;
          }
          continue;
        }
        if (!tag.selfClosing && !voidTags[tag.name]) {
          stack.push(child);
        }
        i = j + 1;
        continue;
      }
    }

    var nextTag = source.indexOf("<", i);
    if (nextTag === -1) nextTag = source.length;
    var text = source.slice(i, nextTag);
    if (text) stack[stack.length - 1].children.push(node(null, {}, [], decodeHTML(text)));
    i = nextTag;
  }

  return root;
}

function textContent(n) {
  if (n.text !== null) return n.text;
  return n.children.map(textContent).join("");
}

function descendants(n, tag) {
  var result = [];
  n.children.forEach(function(child) {
    if (child.tag === tag) result.push(child);
    result = result.concat(descendants(child, tag));
  });
  return result;
}

function lines(value) {
  return String(value || "").split("\n");
}

function block(value) {
  var cleaned = cleanMarkdown(value);
  return cleaned ? "\n\n" + cleaned + "\n\n" : "";
}

function renderChildren(n, context) {
  return n.children.map(function(child) { return renderNode(child, context || {}); }).join("");
}

function inlineText(n) {
  return collapseWhitespace(renderChildren(n, { inline: true }));
}

function renderList(n, ordered, context) {
  var items = n.children.filter(function(child) { return child.tag === "li"; });
  var result = [];
  items.forEach(function(item, index) {
    var marker = ordered ? String(index + 1) + "." : "-";
    var contentLines = lines(cleanMarkdown(renderChildren(item, context || {})));
    if (!contentLines.length || !contentLines[0]) return;
    result.push(marker + " " + contentLines[0]);
    for (var i = 1; i < contentLines.length; i++) result.push("  " + contentLines[i]);
  });
  return result.length ? block(result.join("\n")) : "";
}

function renderHTMLTable(n) {
  var rows = descendants(n, "tr").map(function(row) {
    return row.children
      .filter(function(cell) { return cell.tag === "th" || cell.tag === "td"; })
      .map(function(cell) { return inlineText(cell); });
  }).filter(function(row) { return row.length > 0; });
  return rows.length ? block(renderTable(rows)) : "";
}

function renderNode(n, context) {
  context = context || {};
  if (n.text !== null) return context.pre ? n.text : escapeInline(n.text);
  if (!n.tag) return renderChildren(n, context);

  switch (n.tag) {
    case "script":
    case "style":
    case "meta":
    case "noscript":
    case "svg":
      return "";
    case "br":
      return "\n";
    case "h1":
    case "h2":
    case "h3":
    case "h4":
    case "h5":
    case "h6":
      return block(headingPrefix(parseInt(n.tag.slice(1), 10)) + " " + inlineText(n));
    case "p":
      return block(inlineText(n));
    case "div":
    case "section":
    case "article":
    case "main":
    case "header":
    case "footer":
    case "aside":
    case "body":
    case "html":
      return block(renderChildren(n, context));
    case "blockquote":
      return block(lines(cleanMarkdown(renderChildren(n, context))).map(function(line) {
        return "> " + line;
      }).join("\n"));
    case "pre":
      var code = textContent(n).replace(/^\n+|\n+$/g, "");
      var fence = codeFence(code);
      return block(fence + "\n" + code + "\n" + fence);
    case "code":
      if (context.pre) return textContent(n);
      var codeText = inlineText(n).replace(/`/g, "\\`");
      return codeText ? "`" + codeText + "`" : "";
    case "strong":
    case "b":
      var strong = inlineText(n);
      return strong ? "**" + strong + "**" : "";
    case "em":
    case "i":
      var em = inlineText(n);
      return em ? "*" + em + "*" : "";
    case "s":
    case "strike":
    case "del":
      var del = inlineText(n);
      return del ? "~~" + del + "~~" : "";
    case "a":
      var href = (n.attrs.href || "").trim();
      var title = inlineText(n);
      return href ? markdownLink(title || href, href) : title;
    case "img":
      var src = (n.attrs.src || "").trim();
      return src ? markdownImage(n.attrs.alt || "", src) : "";
    case "ul":
      return renderList(n, false, context);
    case "ol":
      return renderList(n, true, context);
    case "li":
      return renderChildren(n, context);
    case "table":
      return renderHTMLTable(n);
    case "thead":
    case "tbody":
    case "tfoot":
    case "tr":
    case "td":
    case "th":
      return renderChildren(n, context);
    case "hr":
      return block("---");
    default:
      return renderChildren(n, context);
  }
}

function convertHTML(html, sourceURL, includeSourceURL) {
  var root = parseHTML(html);
  var markdown = cleanMarkdown(renderChildren(root, {}));
  if (includeSourceURL && sourceURL) {
    var cleanSource = sanitizedSourceURL(sourceURL);
    markdown = cleanMarkdown([markdown, "Source: " + markdownLink(cleanSource, cleanSource)].filter(Boolean).join("\n\n"));
  }
  return markdown;
}
