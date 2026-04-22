import Configuration
import Logging
import OTel

func makeOTelConfiguration(
  arguments: some AppArguments,
  config: ConfigReader,
  logLevel: Logger.Level? = nil
) -> OTel.Configuration {
  // OTel SDK defaults already match what we want for transport
  // (exporter = .otlp, protocol = httpProtobuf, endpoint = http://localhost:4318);
  // only app-specific values are set here. Operators can override transport
  // defaults via standard OTEL_* environment variables when needed
  // (e.g. running collector on a non-localhost host in compose.yml).
  var configuration = OTel.Configuration.default
  configuration.serviceName = "blindlog-api"
  configuration.diagnosticLogLevel = .warning
  configuration.propagators = [.traceContext]
  configuration.logs.level = .from(logLevel ?? arguments.logLevel ?? .info)

  // K_REVISION is injected by Cloud Run and changes for each deployed revision.
  let cloudRunRevision = config.string(forKey: "k.revision") ?? "unknown"

  configuration.resourceAttributes = [
    "cloud.platform": "gcp_cloud_run",
    "cloud.provider": "gcp",
    "cloud.region": config.string(forKey: "cloud.run.region") ?? "unknown",
    "deployment.environment.name": arguments.env.rawValue,
    "gcp.cloud_run.configuration": config.string(forKey: "k.configuration") ?? "unknown",
    "gcp.cloud_run.revision": cloudRunRevision,
    "gcp.cloud_run.service": config.string(forKey: "k.service") ?? "unknown",
    "service.namespace": "blindlog",
    "service.version": cloudRunRevision,
  ]

  return configuration
}

extension OTel.Configuration.LogLevel {
  fileprivate static func from(_ level: Logger.Level) -> Self {
    switch level {
    case .trace:
      .trace
    case .debug:
      .debug
    case .info, .notice:
      .info
    case .warning:
      .warning
    case .error, .critical:
      .error
    }
  }
}
