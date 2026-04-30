import Foundation

// MARK: - DeveloperSetupMobileSnippetCatalog

enum DeveloperSetupMobileSnippetCatalog {
    // MARK: Internal

    static func flutterHttpClientSnippet(port: Int, certPath: String) -> String {
        """
        import 'dart:convert';
        import 'dart:io';

        \(flutterProxyHostBlock(port: port, certPath: certPath))

        Future<void> runRockxyProbe() async {
          final client = HttpClient();
          client.findProxy = (uri) => 'PROXY ${rockxyProxyHostPort()};';

          // Debug only. Remove this before release builds.
          client.badCertificateCallback = (certificate, host, port) => true;

          final request = await client.getUrl(Uri.parse('https://httpbin.org/get'));
          final response = await request.close();
          final body = await utf8.decodeStream(response);
          print(response.statusCode);
          print(body);
          client.close(force: true);
        }
        """
    }

    static func flutterHTTPPackageSnippet(port: Int, certPath: String) -> String {
        """
        import 'dart:convert';
        import 'dart:io';

        import 'package:http/io_client.dart';

        \(flutterProxyHostBlock(port: port, certPath: certPath))

        Future<void> runRockxyProbe() async {
          final httpClient = HttpClient();
          httpClient.findProxy = (uri) => 'PROXY ${rockxyProxyHostPort()};';

          // Debug only. Remove this before release builds.
          httpClient.badCertificateCallback = (certificate, host, port) => true;

          final client = IOClient(httpClient);
          try {
            final response = await client.get(Uri.parse('https://httpbin.org/get'));
            print(response.statusCode);
            print(jsonDecode(response.body));
          } finally {
            client.close();
          }
        }
        """
    }

    static func flutterDio5Snippet(port: Int, certPath: String) -> String {
        """
        import 'dart:io';

        import 'package:dio/dio.dart';
        import 'package:dio/io.dart';

        \(flutterProxyHostBlock(port: port, certPath: certPath))

        Dio makeRockxyDio() {
          final dio = Dio();
          dio.httpClientAdapter = IOHttpClientAdapter(
            createHttpClient: () {
              final client = HttpClient();
              client.findProxy = (uri) => 'PROXY ${rockxyProxyHostPort()};';

              // Debug only. Remove this before release builds.
              client.badCertificateCallback = (certificate, host, port) => true;
              return client;
            },
            validateCertificate: (certificate, host, port) => true,
          );
          return dio;
        }

        Future<void> runRockxyProbe() async {
          final response = await makeRockxyDio().get('https://httpbin.org/get');
          print(response.statusCode);
          print(response.data);
        }
        """
    }

    static func flutterAndroidNetworkSecurityConfigSnippet(certPath: String) -> String {
        let certPath = escapeForStringLiteral(certPath, language: .dart)
        return """
        <!-- Android debug builds only. Do not ship this trust policy in release builds. -->
        <!-- Install the Rockxy Root CA as a user CA first. Exported PEM hint: \(certPath) -->

        <!-- app/src/debug/res/xml/network_security_config.xml -->
        <?xml version="1.0" encoding="utf-8"?>
        <network-security-config>
            <debug-overrides>
                <trust-anchors>
                    <certificates src="user" />
                    <certificates src="system" />
                </trust-anchors>
            </debug-overrides>
        </network-security-config>

        <!-- app/src/debug/AndroidManifest.xml -->
        <manifest xmlns:android="http://schemas.android.com/apk/res/android">
            <application android:networkSecurityConfig="@xml/network_security_config" />
        </manifest>
        """
    }

    static func reactNativeFetchProbeSnippet(port: Int, certPath: String) -> String {
        let certPath = escapeForStringLiteral(certPath, language: .javaScript)
        return """
        // React Native debug probe.
        // Finish the iOS or Android setup first, then restart Metro and the app.
        // iOS Simulator usually reaches Rockxy through 127.0.0.1:\(port).
        // Android Emulator usually reaches the Mac through 10.0.2.2:\(port).
        // Physical devices need the Device Proxy LAN host and Rockxy's active port.
        // Android trust still depends on a debug build that trusts user CAs.
        // Exported Root CA hint: \(certPath)

        export async function runRockxyReactNativeProbe() {
          const response = await fetch("https://httpbin.org/get", {
            method: "GET",
            headers: {
              "Cache-Control": "no-cache",
            },
          });

          const body = await response.json();
          console.log(response.status);
          console.log(body);
          return body;
        }
        """
    }

    static func reactNativeAndroidNetworkSecurityConfigSnippet(certPath: String) -> String {
        let certPath = escapeForStringLiteral(certPath, language: .javaScript)
        return """
        <!-- Android debug builds only. Do not ship this trust policy in release builds. -->
        <!-- Install the Rockxy Root CA as a user CA first. Exported PEM hint: \(certPath) -->

        <!-- android/app/src/debug/res/xml/network_security_config.xml -->
        <?xml version="1.0" encoding="utf-8"?>
        <network-security-config>
            <debug-overrides>
                <trust-anchors>
                    <certificates src="user" />
                    <certificates src="system" />
                </trust-anchors>
            </debug-overrides>
        </network-security-config>

        <!-- android/app/src/debug/AndroidManifest.xml -->
        <manifest xmlns:android="http://schemas.android.com/apk/res/android">
            <application android:networkSecurityConfig="@xml/network_security_config" />
        </manifest>
        """
    }

    static func reactNativeMetroChecklistSnippet(port: Int, certPath: String) -> String {
        let certPath = escapeForShell(certPath)
        return """
        # React Native Android debugging checklist.
        # Use after Rockxy is running, recording is enabled, and the Root CA is available.
        # Exported Root CA hint:
        #   \(certPath)

        # 1. Keep Metro reachable from the Android runtime.
        adb reverse tcp:8081 tcp:8081

        # 2. Android Emulator proxy host:
        #    Host: 10.0.2.2
        #    Port: \(port)
        #
        # 3. Android Emulator Metro bypass:
        #    Add localhost to the emulator Wi-Fi proxy bypass list.
        #
        # 4. Physical Android device proxy host:
        #    Use the Device Proxy LAN host shown in Rockxy, with port \(port).
        #
        # 5. Physical Android device Metro bypass:
        #    Add the Mac LAN host to the device Wi-Fi proxy bypass list.
        #
        # 6. Restart Metro and cold-launch the app after changing proxy or trust settings.
        npx react-native start --reset-cache
        """
    }

    // MARK: Private

    private enum StringLiteralLanguage {
        case dart
        case javaScript
    }

    private static func flutterProxyHostBlock(port: Int, certPath: String) -> String {
        let certPath = escapeForStringLiteral(certPath, language: .dart)
        return """
        // Debug-only Rockxy proxy values. Pick the runtime that is running this app.
        enum RockxyRuntime { localAppleRuntime, androidEmulator, physicalDevice }
        const rockxyRuntime = RockxyRuntime.localAppleRuntime;

        // localAppleRuntime: iOS Simulator / macOS desktop
        // androidEmulator: Android Emulator
        // physicalDevice: iOS or Android device on the same network
        // Install or share the Rockxy Root CA first. Exported PEM hint: \(certPath)
        const rockxyProxyForSimulator = '127.0.0.1:\(port)';
        const rockxyProxyForAndroidEmulator = '10.0.2.2:\(port)';
        const rockxyProxyForPhysicalDevice = '<LAN device proxy host>:\(port)';

        String rockxyProxyHostPort() {
          switch (rockxyRuntime) {
            case RockxyRuntime.androidEmulator:
              return rockxyProxyForAndroidEmulator;
            case RockxyRuntime.physicalDevice:
              return rockxyProxyForPhysicalDevice;
            case RockxyRuntime.localAppleRuntime:
              return rockxyProxyForSimulator;
          }
        }
        """
    }

    private static func escapeForShell(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func escapeForStringLiteral(_ value: String, language: StringLiteralLanguage) -> String {
        let escaped = value.unicodeScalars.reduce(into: "") { result, scalar in
            switch scalar {
            case "\\":
                result += "\\\\"
            case "\"":
                result += "\\\""
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            default:
                result.append(String(scalar))
            }
        }

        switch language {
        case .dart,
             .javaScript:
            return escaped
        }
    }
}
