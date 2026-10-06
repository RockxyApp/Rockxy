@testable import Rockxy
import Testing

struct FormURLEncodedBodyTests {
    @Test("Form bodies decode + and percent escapes and encode back the way browsers send them")
    func roundTrip() {
        let fields = FormURLEncodedBody.fields(from: "email=a%40b.com&note=hello+world&flag&empty=")
        #expect(fields == [
            .init(name: "email", value: "a@b.com"),
            .init(name: "note", value: "hello world"),
            .init(name: "flag", value: ""),
            .init(name: "empty", value: ""),
        ])
        #expect(FormURLEncodedBody.body(from: [
            .init(name: "q", value: "a b&c=d/é"),
            .init(name: "", value: ""),
        ]) == "q=a+b%26c%3Dd%2F%C3%A9&=")
        let reparsed = FormURLEncodedBody.fields(from: FormURLEncodedBody.body(from: fields))
        #expect(reparsed == fields)
    }

    @Test("Only an enabled form Content-Type turns on the table")
    func detection() {
        #expect(FormURLEncodedBody.isFormContentType([
            EditableReplayHeader(name: "content-type", value: "application/x-www-form-urlencoded; charset=UTF-8"),
        ]))
        #expect(!FormURLEncodedBody.isFormContentType([
            EditableReplayHeader(name: "Content-Type", value: "application/x-www-form-urlencoded", isEnabled: false),
        ]))
        #expect(!FormURLEncodedBody.isFormContentType([EditableReplayHeader(name: "Content-Type", value: "application/json")]))
    }
}
