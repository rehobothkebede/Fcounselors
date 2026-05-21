import SwiftUI
import UIKit

// MARK: - Code Block View

struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var copied = false

    private var displayLanguage: String {
        language.isEmpty ? "text" : language.lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider().overlay(Color(red: 0.26, green: 0.26, blue: 0.32))
            codeContent
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(red: 0.26, green: 0.26, blue: 0.32), lineWidth: 1)
        )
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(languageDotColor)
                .frame(width: 8, height: 8)
            Text(displayLanguage)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.60, green: 0.65, blue: 0.72))
            Spacer()
            Button {
                UIPasteboard.general.string = code
                withAnimation(.spring(duration: 0.2)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.spring(duration: 0.2)) { copied = false }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "square.on.square")
                        .font(.system(size: 11, weight: .medium))
                    Text(copied ? "Copied!" : "Copy")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(
                    copied
                        ? Color(red: 0.38, green: 0.90, blue: 0.50)
                        : Color(red: 0.55, green: 0.60, blue: 0.65)
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(red: 0.15, green: 0.15, blue: 0.19))
    }

    private var codeContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(SyntaxHighlighter(language: displayLanguage).highlight(code))
                .font(.system(size: 13, design: .monospaced))
                .lineSpacing(5)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(red: 0.10, green: 0.10, blue: 0.13))
    }

    private var languageDotColor: Color {
        switch displayLanguage {
        case "c":              return Color(red: 0.36, green: 0.68, blue: 0.93)
        case "cpp", "c++":    return Color(red: 0.60, green: 0.44, blue: 0.90)
        case "python":         return Color(red: 0.27, green: 0.75, blue: 0.43)
        case "java":           return Color(red: 0.93, green: 0.60, blue: 0.27)
        case "swift":          return Color(red: 0.98, green: 0.45, blue: 0.34)
        case "javascript", "js", "jsx": return Color(red: 0.96, green: 0.82, blue: 0.24)
        case "typescript", "ts", "tsx": return Color(red: 0.24, green: 0.55, blue: 0.93)
        case "bash", "sh", "shell", "zsh": return Color(red: 0.50, green: 0.90, blue: 0.50)
        default:               return Color(red: 0.50, green: 0.55, blue: 0.62)
        }
    }
}

// MARK: - Syntax Highlighter

struct SyntaxHighlighter {
    let language: String

    // VS Code Dark+ inspired palette
    private let defaultColor      = Color(red: 0.85, green: 0.85, blue: 0.88)
    private let keywordColor      = Color(red: 0.83, green: 0.56, blue: 1.00)   // purple
    private let typeColor         = Color(red: 0.36, green: 0.86, blue: 0.95)   // cyan
    private let stringColor       = Color(red: 0.60, green: 0.87, blue: 0.60)   // green
    private let commentColor      = Color(red: 0.40, green: 0.48, blue: 0.55)   // gray
    private let numberColor       = Color(red: 1.00, green: 0.76, blue: 0.40)   // amber
    private let preprocessorColor = Color(red: 0.55, green: 0.80, blue: 1.00)   // sky blue

    func highlight(_ code: String) -> AttributedString {
        let lines = code.components(separatedBy: "\n")
        var result = AttributedString()
        for (i, line) in lines.enumerated() {
            result += highlightLine(line)
            if i < lines.count - 1 {
                result += AttributedString("\n")
            }
        }
        return result
    }

    private func highlightLine(_ line: String) -> AttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("//") {
            return colored(line, commentColor)
        }
        if language == "python" && trimmed.hasPrefix("#") {
            return colored(line, commentColor)
        }
        if trimmed.hasPrefix("#") && cFamily.contains(language) {
            return colored(line, preprocessorColor)
        }

        return tokenize(line)
    }

    private func tokenize(_ line: String) -> AttributedString {
        var result = AttributedString()
        var i = line.startIndex

        while i < line.endIndex {
            let ch = line[i]
            let next = line.index(after: i)

            // C-style line comment
            if ch == "/" && next < line.endIndex && line[next] == "/" {
                result += colored(String(line[i...]), commentColor)
                break
            }
            // Python/shell inline comment
            if ch == "#" && scriptLangs.contains(language) {
                result += colored(String(line[i...]), commentColor)
                break
            }
            // String literals (double or single quote)
            if ch == "\"" || ch == "'" {
                let (str, end) = extractString(from: line, at: i, quote: ch)
                result += colored(str, stringColor)
                i = end
                continue
            }
            // Numeric literals
            if ch.isNumber {
                let (num, end) = extractWhile(from: line, at: i) {
                    $0.isNumber || $0 == "." || $0 == "x" || $0 == "X" || $0 == "b" || $0 == "B" ||
                    ($0 >= "a" && $0 <= "f") || ($0 >= "A" && $0 <= "F") ||
                    $0 == "u" || $0 == "U" || $0 == "l" || $0 == "L" || $0 == "f" || $0 == "F"
                }
                result += colored(num, numberColor)
                i = end
                continue
            }
            // Identifiers, keywords, types
            if ch.isLetter || ch == "_" {
                let (word, end) = extractWhile(from: line, at: i) { $0.isLetter || $0.isNumber || $0 == "_" }
                result += colored(word, colorFor(word))
                i = end
                continue
            }
            // Everything else
            result += colored(String(ch), defaultColor)
            i = next
        }

        return result
    }

    private func colorFor(_ word: String) -> Color {
        if allKeywords.contains(word) { return keywordColor }
        if allTypes.contains(word)    { return typeColor }
        return defaultColor
    }

    private var cFamily:     Set<String> { ["c", "cpp", "c++", "objc", "objective-c"] }
    private var scriptLangs: Set<String> { ["python", "bash", "sh", "shell", "zsh", "ruby"] }

    private var allKeywords: Set<String> {
        switch language {
        case "c", "objc", "objective-c":
            return ["if","else","for","while","do","return","break","continue","switch","case",
                    "default","struct","typedef","sizeof","enum","union","goto","inline",
                    "restrict","volatile","extern","static","const","auto","register",
                    "NULL","true","false"]
        case "cpp", "c++":
            return ["if","else","for","while","do","return","break","continue","switch","case",
                    "default","struct","typedef","sizeof","enum","union","goto","inline",
                    "restrict","volatile","extern","static","const","auto","register",
                    "NULL","true","false","nullptr","class","public","private","protected",
                    "new","delete","virtual","override","template","typename","namespace",
                    "using","this","throw","try","catch","noexcept","final","constexpr",
                    "explicit","friend","mutable","operator","decltype","static_assert"]
        case "python":
            return ["if","elif","else","for","while","in","not","and","or","return","break",
                    "continue","pass","def","class","import","from","as","with","yield",
                    "lambda","try","except","finally","raise","assert","del","global",
                    "nonlocal","True","False","None","is","print","len","range","self",
                    "super","async","await","match","case"]
        case "java":
            return ["if","else","for","while","do","return","break","continue","switch","case",
                    "default","class","interface","extends","implements","new","this","super",
                    "static","final","abstract","public","private","protected","try","catch",
                    "finally","throw","throws","import","package","null","true","false",
                    "instanceof","synchronized","volatile","transient","native","enum","assert"]
        case "swift":
            return ["if","else","for","while","in","return","break","continue","switch","case",
                    "default","class","struct","enum","protocol","extension","func","var","let",
                    "guard","defer","throw","throws","try","catch","import","typealias","init",
                    "deinit","self","super","true","false","nil","where","as","is","some","any",
                    "override","final","public","private","internal","fileprivate","open",
                    "mutating","nonmutating","lazy","weak","unowned","static","subscript",
                    "willSet","didSet","get","set","async","await","actor","nonisolated"]
        case "javascript","js","jsx":
            return ["if","else","for","while","do","return","break","continue","switch","case",
                    "default","class","function","var","let","const","new","this","super",
                    "import","export","from","extends","null","undefined","true","false",
                    "typeof","instanceof","in","of","try","catch","finally","throw",
                    "async","await","yield","delete","void","debugger"]
        case "typescript","ts","tsx":
            return ["if","else","for","while","do","return","break","continue","switch","case",
                    "default","class","function","var","let","const","new","this","super",
                    "import","export","from","extends","implements","null","undefined","true","false",
                    "typeof","instanceof","in","of","try","catch","finally","throw",
                    "async","await","yield","delete","void","interface","type","enum",
                    "namespace","abstract","declare","readonly","override","as","is",
                    "any","never","unknown","keyof","infer"]
        case "bash","sh","shell","zsh":
            return ["if","then","else","elif","fi","for","in","do","done","while","until",
                    "case","esac","function","return","exit","echo","export","local",
                    "readonly","source","alias","unset","shift","trap","true","false"]
        default:
            return ["if","else","for","while","return","break","continue","true","false","null","NULL"]
        }
    }

    private var allTypes: Set<String> {
        switch language {
        case "c", "objc", "objective-c":
            return ["int","char","float","double","long","short","unsigned","signed","void","bool",
                    "size_t","ssize_t","ptrdiff_t","uint8_t","uint16_t","uint32_t","uint64_t",
                    "int8_t","int16_t","int32_t","int64_t","wchar_t","FILE",
                    "BOOL","NSString","NSArray","NSDictionary","NSInteger","NSUInteger","CGFloat"]
        case "cpp", "c++":
            return ["int","char","float","double","long","short","unsigned","signed","void","bool",
                    "size_t","string","wstring","vector","array","map","unordered_map",
                    "set","unordered_set","pair","tuple","list","deque","queue","stack",
                    "priority_queue","shared_ptr","unique_ptr","weak_ptr",
                    "uint8_t","uint16_t","uint32_t","uint64_t","int8_t","int16_t","int32_t","int64_t",
                    "ostream","istream","ifstream","ofstream","fstream","stringstream"]
        case "python":
            return ["int","str","float","bool","list","dict","tuple","set","bytes","bytearray",
                    "complex","frozenset","type","object","Exception","ValueError","TypeError",
                    "KeyError","IndexError","AttributeError","RuntimeError","StopIteration",
                    "NotImplementedError","IOError","OSError"]
        case "java":
            return ["int","char","float","double","long","short","byte","boolean","void",
                    "String","Integer","Double","Float","Long","Short","Byte","Boolean",
                    "Character","Object","Number","List","ArrayList","LinkedList",
                    "Map","HashMap","TreeMap","Set","HashSet","TreeSet","Queue",
                    "Stack","Arrays","System","Math","StringBuilder","Scanner"]
        case "swift":
            return ["Int","Int8","Int16","Int32","Int64","UInt","UInt8","UInt16","UInt32","UInt64",
                    "String","Character","Double","Float","Bool","Optional","Data","Date",
                    "URL","UUID","Array","Dictionary","Set","Never","Void","Any","AnyObject",
                    "CGFloat","CGPoint","CGRect","CGSize",
                    "View","Text","Color","Image","Button","VStack","HStack","ZStack",
                    "ScrollView","List","NavigationView","NavigationStack",
                    "EnvironmentObject","StateObject","ObservedObject","Published","State","Binding"]
        case "javascript","js","jsx","typescript","ts","tsx":
            return ["number","string","boolean","object","symbol","bigint","Array","Object",
                    "Promise","Map","Set","WeakMap","WeakSet","Date","RegExp","Error",
                    "Function","Math","JSON","console","window","document","Element",
                    "HTMLElement","Event","MouseEvent","KeyboardEvent","Response","Request"]
        default:
            return []
        }
    }

    // MARK: - Helpers

    private func colored(_ str: String, _ color: Color) -> AttributedString {
        var attr = AttributedString(str)
        attr.foregroundColor = color
        return attr
    }

    private func extractString(from line: String, at start: String.Index, quote: Character) -> (String, String.Index) {
        var i = line.index(after: start)
        while i < line.endIndex {
            if line[i] == "\\" {
                let next = line.index(after: i)
                if next < line.endIndex {
                    i = line.index(after: next)
                    continue
                }
            }
            if line[i] == quote {
                let end = line.index(after: i)
                return (String(line[start..<end]), end)
            }
            i = line.index(after: i)
        }
        return (String(line[start...]), line.endIndex)
    }

    private func extractWhile(from line: String, at start: String.Index, while predicate: (Character) -> Bool) -> (String, String.Index) {
        var i = start
        while i < line.endIndex && predicate(line[i]) {
            i = line.index(after: i)
        }
        return (String(line[start..<i]), i)
    }
}
