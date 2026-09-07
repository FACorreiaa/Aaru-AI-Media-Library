import aaruAPI
import OpenAPIRuntime

struct APIImplementation: APIProtocol {
    func getHello(_ input: aaruAPI.Operations.GetHello.Input) async throws -> aaruAPI.Operations.GetHello.Output {
        return .ok(.init(body: .plainText("Hello!")))
    }
}
