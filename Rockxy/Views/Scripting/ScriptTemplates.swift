import Foundation

/// Shipped script templates and the "new script" default source. Uses the
/// multi-arg JS API (`onRequest(context, url, request)` /
/// `onResponse(context, url, request, response)`) with the full comment
/// scaffolding so users can discover what's editable.
enum ScriptTemplates {
    /// The default source used when the user creates a new script via `+`.
    /// Uses the multi-arg JS API which the runtime dispatches automatically
    /// (function `length` is 3 or 4).
    static let defaultSource: String = """
    /// This func is called if the Request Checkbox is Enabled. You can modify the Request Data here before the request hits the server.
    /// e.g. Add/Update/Remove: method, path, headers, queries, comment, color and body (json, form, plain-text, Uint8Array for Binary Body)
    ///
    function onRequest(context, url, request) {
      // console.log(request);
      console.log(url);

      // Update or Add new headers
      // request.headers["X-New-Headers"] = "My-Value";

      // Update or Add new queries
      // request.queries["name"] = "Rockxy";

      // Body (a string; parse it when you need structured edits)
      // var body = JSON.parse(request.body);
      // body["new-key"] = "new-value";
      // request.body = JSON.stringify(body);

      // Done
      return request;
    }

    /// This func is called if the Response Checkbox is Enabled. You can modify the Response Data here before it goes to the client
    /// e.g. Add/Update/Remove: headers, statusCode, comment, color and body (json, plain-text, Uint8Array for Binary Body)
    ///
    function onResponse(context, url, request, response) {
      // console.log(response);

      // Update or Add new headers
      // response.headers["Content-Type"] = "application/json";

      // Update status Code
      // response.statusCode = 500;

      // Update Body (a string; compressed responses arrive already decoded)
      // var body = JSON.parse(response.body);
      // body["new-key"] = "Rockxy";
      // response.body = JSON.stringify(body);

      // Or map a local file as a body
      // response.bodyFilePath = "~/Desktop/myfile.json"

      // Done
      return response;
    }
    """
}

// MARK: - ScriptStarterTemplate

/// Ready-to-run starting points offered when creating a script. Each template is complete and
/// valid as written; mock templates also turn on Run as Mock so the request never goes upstream.
enum ScriptStarterTemplate: String, CaseIterable, Identifiable {
    case modifyHeaders
    case logRequests
    case blockPattern
    case customResponse
    case rewriteURL
    case conditionalMockJSON

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .modifyHeaders:
            String(localized: "Modify Headers", bundle: RockxyLocalization.bundle)
        case .logRequests:
            String(localized: "Log Requests", bundle: RockxyLocalization.bundle)
        case .blockPattern:
            String(localized: "Block Pattern", bundle: RockxyLocalization.bundle)
        case .customResponse:
            String(localized: "Custom Response", bundle: RockxyLocalization.bundle)
        case .rewriteURL:
            String(localized: "Rewrite URL", bundle: RockxyLocalization.bundle)
        case .conditionalMockJSON:
            String(localized: "Conditional Mock JSON", bundle: RockxyLocalization.bundle)
        }
    }

    var summary: String {
        switch self {
        case .modifyHeaders:
            String(localized: "Add a header to every matching request.", bundle: RockxyLocalization.bundle)
        case .logRequests:
            String(localized: "Print each request's method and URL to the console.", bundle: RockxyLocalization.bundle)
        case .blockPattern:
            String(localized: "Block requests whose URL contains a word.", bundle: RockxyLocalization.bundle)
        case .customResponse:
            String(localized: "Answer locally with your own JSON response.", bundle: RockxyLocalization.bundle)
        case .rewriteURL:
            String(localized: "Change the path of matching requests.", bundle: RockxyLocalization.bundle)
        case .conditionalMockJSON:
            String(
                localized: "Mock some paths and pass the rest through unchanged.",
                bundle: RockxyLocalization.bundle
            )
        }
    }

    var systemImage: String {
        switch self {
        case .modifyHeaders: "list.bullet.rectangle"
        case .logRequests: "text.alignleft"
        case .blockPattern: "nosign"
        case .customResponse: "doc.text"
        case .rewriteURL: "arrow.triangle.branch"
        case .conditionalMockJSON: "curlybraces"
        }
    }

    var behavior: ScriptBehavior {
        switch self {
        case .modifyHeaders,
             .logRequests,
             .blockPattern,
             .rewriteURL:
            ScriptBehavior(runOnRequest: true, runOnResponse: false, runAsMock: false)
        case .customResponse,
             .conditionalMockJSON:
            ScriptBehavior(runOnRequest: true, runOnResponse: false, runAsMock: true)
        }
    }

    var source: String {
        switch self {
        case .modifyHeaders:
            """
            /// Adds a header to every matching request before it reaches the server.
            function onRequest(context, url, request) {
              request.headers["X-Debug-Client"] = "Rockxy";
              return request;
            }
            """
        case .logRequests:
            """
            /// Prints each matching request to the script console without changing it.
            function onRequest(context, url, request) {
              console.log(request.method + " " + url);
              return request;
            }
            """
        case .blockPattern:
            """
            /// Returning null blocks the request locally with HTTP 403; it never reaches the server.
            const blockedWord = "analytics";

            function onRequest(context, url, request) {
              if (url.includes(blockedWord)) {
                return null;
              }
              return request;
            }
            """
        case .customResponse:
            """
            /// Run as Mock is on: the returned object is sent to the client and the request
            /// never goes upstream. statusCode must be between 100 and 599.
            function onRequest(context, url, request) {
              return {
                statusCode: 200,
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ message: "Hello from Rockxy", path: request.path })
              };
            }
            """
        case .rewriteURL:
            """
            /// Changes the path of matching requests. Host, port, and scheme cannot change here;
            /// use Map Remote to send a request to another server.
            function onRequest(context, url, request) {
              request.path = request.path.replace("/v1/", "/v2/");
              return request;
            }
            """
        case .conditionalMockJSON:
            """
            /// Run as Mock is on, so every matching request is answered locally. Paths listed in
            /// `mocks` get their JSON; anything else gets a 404 so a missing mock is obvious.
            const mocks = {
              "/api/user": { id: 1, name: "Ada" },
              "/api/flags": { newCheckout: true }
            };

            function onRequest(context, url, request) {
              const body = mocks[request.path];
              if (body === undefined) {
                return {
                  statusCode: 404,
                  headers: { "Content-Type": "application/json" },
                  body: JSON.stringify({ error: "No mock for " + request.path })
                };
              }
              return {
                statusCode: 200,
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(body)
              };
            }
            """
        }
    }
}
