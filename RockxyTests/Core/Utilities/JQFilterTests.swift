import Foundation
@testable import Rockxy
import Testing

// MARK: - JQFilterTests

struct JQFilterTests {
    // MARK: Internal

    @Test("Paths, iteration, slices, and optional access")
    func paths() throws {
        #expect(try run(".store.book[0].title") == [#""Sayings""#])
        #expect(try run(".store.book[].price") == ["8.95", "12.99", "22"])
        #expect(try run(".store.book[-1:] | length") == ["1"])
        #expect(try run(".store.book[1:][0].author") == [#""Evelyn""#])
        #expect(try run(".missing.deeper") == ["null"])
        #expect(try run(".store.book[0].title[0:4]") == [#""Sayi""#])
        #expect(try run(#".["store"]."book" | length"#) == ["3"])
        #expect(try run(".store.bicycle[]?") == [#""red""#, "19.95"])
        #expect(try run("[.store.book[].title?]| length") == ["3"])
        #expect(try run("[..|numbers] | add") == ["73.89"])
    }

    @Test("Select, map, construction, and comparisons")
    func transforms() throws {
        #expect(try run("[.store.book[] | select(.price < 10) | .author]") == [#"["Nigel"]"#])
        #expect(try run("[.store.book[] | {t: .title, cheap: (.price < 15)}] | map(.cheap)") == ["[true,true,false]"])
        #expect(try run(#"{(.store.bicycle.color): 1}"#) == [#"{"red":1}"#])
        #expect(try run("{a: (1,2)} | .a") == ["1", "2"])
        #expect(try run(".store.book | map(.price) | sort | reverse | first") == ["22"])
        #expect(try run(".store.book | sort_by(.author) | map(.author)") == [#"["Evelyn","J. R. R.","Nigel"]"#])
        #expect(try run(".store.book | group_by(.category) | map(length)") == ["[2,1]"])
        #expect(try run(".store.book | min_by(.price) | .title") == [#""Sayings""#])
        #expect(try run(".store.book | max_by(.price) | .title") == [#""Rings""#])
        #expect(try run(#"[.store.book[].category] | unique"#) == [#"["fiction","reference"]"#])
        #expect(try run(".store.book | any(.price > 20)") == ["true"])
        #expect(try run(".store.book | all(.price > 20)") == ["false"])
        #expect(try run("[.store.book[] | .price] | add / length | floor") == ["14"])
    }

    @Test("Objects keep document order; keys sorts; to_entries and with_entries")
    func objects() throws {
        #expect(try run(#".store.bicycle | keys"#) == [#"["color","price"]"#])
        #expect(try run(#"{"z":1,"a":2} | keys_unsorted"#) == [#"["z","a"]"#])
        #expect(try run(#"{"z":1,"a":2}"#) == [#"{"z":1,"a":2}"#])
        #expect(try run(#"{"a":1,"b":2} | with_entries(.value += 10)"#) == [#"{"a":11,"b":12}"#])
        #expect(try run(#"{"a":1} | to_entries"#) == [#"[{"key":"a","value":1}]"#])
        #expect(try run(#"[{"name":"x","value":1}] | from_entries"#) == [#"{"x":1}"#])
        #expect(try run(#"{"a":{"b":1}} * {"a":{"c":2}}"#) == [#"{"a":{"b":1,"c":2}}"#])
        #expect(try run(#"{"a":1} + {"b":2} | has("b")"#) == ["true"])
        #expect(try run(#"[paths] | length"#, input: #"{"a":[1,{"b":2}]}"#) == ["4"])
        #expect(try run(#"[leaf_paths]"#, input: #"{"a":[1,{"b":2}]}"#) == [#"[["a",0],["a",1,"b"]]"#])
    }

    @Test("Assignment, update, and deletion")
    func updates() throws {
        #expect(try run(".store.bicycle.price = 1 | .store.bicycle") == [#"{"color":"red","price":1}"#])
        #expect(try run(".store.book[].price |= . * 2 | [.store.book[].price]") == ["[17.9,25.98,44]"])
        #expect(try run(".store.book[0].price += 1 | .store.book[0].price") == ["9.95"])
        #expect(try run("del(.store.book[] | select(.price > 10)) | .store.book | length") == ["1"])
        #expect(try run("del(.store) | keys") == [#"["expensive"]"#])
        #expect(try run(".a.b.c = 1", input: "null") == [#"{"a":{"b":{"c":1}}}"#])
        #expect(try run(".[2] = 1", input: "[]") == ["[null,null,1]"])
        #expect(try run(#".missing //= "d" | .missing"#) == [#""d""#])
        #expect(try run("to_entries | map(select(.key != \"store\")) | from_entries") == [#"{"expensive":10}"#])
        #expect(try run("[path(..)] | length", input: "[[1]]") == ["3"])
        #expect(try run("getpath([\"store\",\"bicycle\",\"color\"])") == [#""red""#])
        #expect(try run("setpath([\"x\"]; 1) | .x") == ["1"])
    }

    @Test("Control flow: if, try, alternative, reduce, foreach, variables, limit")
    func controlFlow() throws {
        #expect(try run("if .expensive > 5 then \"big\" elif .expensive > 1 then \"mid\" else \"small\" end") ==
            [#""big""#])
        #expect(try !run("if false then 1 end").isEmpty)
        #expect(try run("try error(\"boom\") catch .") == [#""boom""#])
        #expect(try run(".store.book[0].title | tonumber?").isEmpty)
        #expect(try run("(.nope // \"fallback\")") == [#""fallback""#])
        #expect(try run("reduce .store.book[] as $b (0; . + $b.price)") == ["43.94"])
        #expect(try run("[foreach (1,2,3) as $x (0; . + $x)]") == ["[1,3,6]"])
        #expect(try run(".expensive as $e | [.store.book[] | select(.price > $e) | .title]") ==
            [#"["Honour","Rings"]"#])
        #expect(try run("[limit(2; .store.book[])] | length") == ["2"])
        #expect(try run("first(range(10; 0; -3))") == ["10"])
        #expect(try run("[range(5)] | .[1:3]") == ["[1,2]"])
        #expect(try run("[.[] | numbers]", input: #"[1,"a",null,2]"#) == ["[1,2]"])
        #expect(try run("isempty(empty)") == ["true"])
        #expect(try run("[1,[2,[3]]] | flatten") == ["[1,2,3]"])
        #expect(try run("[1,2] | contains([1])") == ["true"])
        #expect(try run("[.[] | tostring]", input: "[1,\"a\",[2]]") == [#"["1","a","[2]"]"#])
        #expect(try run("[until(. > 100; . * 2)]", input: "1") == ["[128]"])
    }

    @Test("Strings: interpolation, regex, split/join, formats")
    func strings() throws {
        #expect(try run(#""Book: \(.store.book[0].title)!""#) == [#""Book: Sayings!""#])
        #expect(try run(#".store.book[0].author | test("^ni"; "i")"#) == ["true"])
        #expect(try run(#""a-b-c" | split("-") | join("+")"#) == [#""a+b+c""#])
        #expect(try run(#""a1b22c" | [scan("[0-9]+")]"#) == [#"["1","22"]"#])
        #expect(try run(#""2024-05-06" | capture("(?<y>\\d+)-(?<m>\\d+)")"#) == [#"{"y":"2024","m":"05"}"#])
        #expect(try run(#""hello world" | gsub("o"; "0")"#) == [#""hell0 w0rld""#])
        #expect(try run(#""abc" | sub("(?<x>b)"; "[\(.x)]")"#) == [#""a[b]c""#])
        #expect(try run(#""abc" | match("b").offset"#) == ["1"])
        #expect(try run(#"["a","b,c"] | @csv"#) == [#""\"a\",\"b,c\"""#])
        #expect(try run(#""hi" | @base64 | @base64d"#) == [#""hi""#])
        #expect(try run(#"@uri "q=\("a b&c")""#) == [#""q=a%20b%26c""#])
        #expect(try run(#""  x  " | trim, ltrimstr(" ")"#) == [#""x""#, #"" x  ""#])
        #expect(try run(#""abc" | ascii_upcase | explode | implode"#) == [#""ABC""#])
        #expect(try run(#""a,b" | [splits(",")]"#) == [#"["a","b"]"#])
        #expect(try run(#""abcb" | indices("b")"#) == ["[1,3]"])
        #expect(try run(#"{"a":1} | tojson | fromjson | .a"#) == ["1"])
        #expect(try run(#"1700000000 | todate"#) == [#""2023-11-14T22:13:20Z""#])
    }

    @Test("Syntax errors, runtime errors, and resource limits are reported, not crashes")
    func failures() throws {
        #expect(throws: JQError.self) { try JQFilter(".a[") }
        #expect(throws: JQError.self) { try JQFilter("def f: 1; f") }
        #expect(throws: JQError.syntax("The filter ends before it is complete.")) { try JQFilter(".a | select(") }
        #expect(throws: (any Error).self) { try run(".store | .[0]") }
        #expect(throws: (any Error).self) { try run("{} | length | .foo") }
        let limits = JQLimits(maxSteps: 10_000, maxOutputs: 10_000, maxDepth: 256, maxRegexPatternLength: 64)
        #expect(throws: JQError.self) {
            try JQFilter("[range(1e9)]").run(.null, limits: limits)
        }
        #expect(throws: JQError.self) {
            try JQFilter("[repeat(.)]").run(.number(1), limits: limits)
        }
        let capped = try JQFilter("range(100)").run(.null, limits: JQLimits(maxOutputs: 5))
        #expect(capped.values.count == 5)
        #expect(capped.isTruncated)
        let limited = try JQFilter("[limit(3; range(100))] | length").run(.null, limits: JQLimits(maxOutputs: 5))
        #expect(limited.values == [.number(3)])
    }

    @Test("$ENV never exposes the app's environment")
    func environmentIsHidden() throws {
        #expect(try run("$ENV | length") == ["0"])
        #expect(try run("env | keys") == ["[]"])
    }

    @Test("The JSON reader keeps key order and handles escapes and unicode")
    func reader() throws {
        let value = try JQValue.parse(#"{"b":"é😀","a":[1e2,-0.5,true,null]}"#)
        #expect(value.jsonText() == #"{"b":"é😀","a":[100,-0.5,true,null]}"#)
        #expect(throws: JQError.self) { try JQValue.parse(#"{"a":1,}"#) }
        #expect(value.jsonText(pretty: true).contains("\n  \"a\": [\n    100,"))
    }

    // MARK: Private

    private static let store = """
    {"store":{"book":[
      {"category":"reference","author":"Nigel","title":"Sayings","price":8.95},
      {"category":"fiction","author":"Evelyn","title":"Honour","price":12.99},
      {"category":"fiction","author":"J. R. R.","title":"Rings","price":22}
    ],"bicycle":{"color":"red","price":19.95}},"expensive":10}
    """

    private func run(_ filter: String, input: String = JQFilterTests.store) throws -> [String] {
        try JQFilter(filter).run(JQValue.parse(input)).values.map { $0.jsonText() }
    }
}
