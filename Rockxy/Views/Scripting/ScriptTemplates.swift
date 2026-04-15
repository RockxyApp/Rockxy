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

      // Body
      // var body = request.body;
      // body["new-key"] = "new-value"
      // request.body = body;

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

      // Update Body
      // var body = response.body;
      // body["new-key"] = "Rockxy";
      // response.body = body;

      // Or map a local file as a body
      // response.bodyFilePath = "~/Desktop/myfile.json"

      // Done
      return response;
    }
    """
}
