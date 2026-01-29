// logger.ts - Structured logging utilities for Cloud Logging

enum LogLevel {
  DEBUG = "DEBUG",
  INFO = "INFO",
  WARN = "WARN",
  ERROR = "ERROR",
}

interface LogContext {
  function?: string;
  uid?: string;
  [key: string]: unknown;
}

/**
 * Sanitize objects for logging by redacting sensitive values.
 * Use this before logging any object that might contain secrets.
 */
export function sanitizeForLog(obj: Record<string, unknown>): Record<string, unknown> {
  const sensitiveKeys = ["key", "token", "secret", "password", "apiKey", "api_key", "authorization"];
  const sanitized: Record<string, unknown> = {};

  for (const [k, v] of Object.entries(obj)) {
    const keyLower = k.toLowerCase();
    if (sensitiveKeys.some((s) => keyLower.includes(s))) {
      sanitized[k] = typeof v === "string" ? `${v.slice(0, 4)}...` : "[REDACTED]";
    } else if (typeof v === "object" && v !== null && !Array.isArray(v)) {
      sanitized[k] = sanitizeForLog(v as Record<string, unknown>);
    } else {
      sanitized[k] = v;
    }
  }

  return sanitized;
}

/**
 * Structured logger for Firebase Cloud Functions.
 * Outputs JSON format compatible with Cloud Logging.
 */
export class Logger {
  private context: LogContext;

  constructor(context: LogContext = {}) {
    this.context = context;
  }

  private log(level: LogLevel, message: string, data?: unknown) {
    const entry = {
      timestamp: new Date().toISOString(),
      severity: level, // Cloud Logging uses 'severity'
      message,
      ...this.context,
      ...(data ? { data } : {}),
    };

    // JSON format for structured logging
    console.log(JSON.stringify(entry));
  }

  debug(message: string, data?: unknown) {
    this.log(LogLevel.DEBUG, message, data);
  }

  info(message: string, data?: unknown) {
    this.log(LogLevel.INFO, message, data);
  }

  warn(message: string, data?: unknown) {
    this.log(LogLevel.WARN, message, data);
  }

  error(message: string, error?: unknown) {
    this.log(LogLevel.ERROR, message, {
      error:
        error instanceof Error
          ? {
              message: error.message,
              stack: error.stack,
              name: error.name,
            }
          : error,
    });
  }

  /**
   * Create a child logger with additional context.
   */
  child(context: LogContext): Logger {
    return new Logger({ ...this.context, ...context });
  }
}

/**
 * Create a logger for a specific function.
 */
export function createLogger(functionName: string, uid?: string): Logger {
  return new Logger({ function: functionName, uid });
}
