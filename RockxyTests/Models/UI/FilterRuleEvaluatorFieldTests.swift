import Foundation
@testable import Rockxy
import Testing

// MARK: - FilterRuleEvaluatorFieldTests

struct FilterRuleEvaluatorFieldTests {
    @Test("GraphQL Operation matches the parsed operation name")
    func graphQLOperationField() {
        let search = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/graphql")
        search.graphQLInfo = GraphQLInfo(
            operationName: "SearchProducts",
            operationType: .query,
            query: "query SearchProducts { products { id } }",
            variables: nil
        )
        let anonymous = TestFixtures.makeTransaction(method: "POST", url: "https://api.example.com/graphql")
        let rule = FilterRule(field: .graphQLOperation, filterOperator: .is, value: "searchproducts")

        #expect(FilterRuleEvaluator.matches(search, rules: [rule]))
        #expect(!FilterRuleEvaluator.matches(anonymous, rules: [rule]))
    }

    @Test("All Fields finds a value in the response body")
    func allFieldsSearchesBodies() {
        let transaction = TestFixtures.makeTransaction(url: "https://api.example.com/profile")
        transaction.response = HTTPResponseData(
            statusCode: 401,
            statusMessage: "Unauthorized",
            headers: [HTTPHeader(name: "WWW-Authenticate", value: "Bearer")],
            body: Data(#"{"error":"token_expired"}"#.utf8)
        )

        #expect(FilterRuleEvaluator.matches(
            transaction,
            rules: [FilterRule(field: .all, filterOperator: .contains, value: "token_expired")]
        ))
        #expect(FilterRuleEvaluator.matches(
            transaction,
            rules: [FilterRule(field: .all, filterOperator: .contains, value: "www-authenticate")]
        ))
        #expect(!FilterRuleEvaluator.matches(
            transaction,
            rules: [FilterRule(field: .all, filterOperator: .contains, value: "not-present")]
        ))
    }

    @Test("Status 401 OR 403 keeps both rows")
    func orConnectorAcrossStatuses() {
        let unauthorized = TestFixtures.makeTransaction(statusCode: 401)
        let forbidden = TestFixtures.makeTransaction(statusCode: 403)
        let ok = TestFixtures.makeTransaction(statusCode: 200)
        let rules = [
            FilterRule(field: .statusCode, filterOperator: .is, value: "401"),
            FilterRule(connector: .or, field: .statusCode, filterOperator: .is, value: "403"),
        ]

        #expect(FilterRuleEvaluator.matches(unauthorized, rules: rules))
        #expect(FilterRuleEvaluator.matches(forbidden, rules: rules))
        #expect(!FilterRuleEvaluator.matches(ok, rules: rules))
    }
}
