// errors.ts - Standardized error handling utilities
import { HttpsError } from "firebase-functions/v2/https";

export class FunctionErrors {
  static auth(): HttpsError {
    return new HttpsError("unauthenticated", "Authentication required");
  }

  static missingConfig(service: string): HttpsError {
    return new HttpsError("internal", `${service} configuration missing`);
  }

  static invalidArg(field: string, reason: string): HttpsError {
    return new HttpsError("invalid-argument", `${field}: ${reason}`);
  }

  static notFound(resource: string): HttpsError {
    return new HttpsError("not-found", `${resource} not found`);
  }

  static permissionDenied(reason?: string): HttpsError {
    return new HttpsError(
      "permission-denied",
      reason || "You do not have permission to perform this action"
    );
  }

  static resourceExhausted(reason?: string): HttpsError {
    return new HttpsError(
      "resource-exhausted",
      reason || "Too many requests. Please wait before trying again."
    );
  }

  static failedPrecondition(reason: string): HttpsError {
    return new HttpsError("failed-precondition", reason);
  }

  static unexpected(message?: string): HttpsError {
    return new HttpsError("internal", message || "An unexpected error occurred");
  }
}
