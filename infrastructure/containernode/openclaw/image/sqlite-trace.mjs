import { DatabaseSync, StatementSync } from "node:sqlite";
import { threadId } from "node:worker_threads";

const TRACE_PREFIX = "[sqlite-trace]";
const lockCodes = new Set(["SQLITE_BUSY", "SQLITE_LOCKED", 5, 6]);

function isLockError(error) {
  const code = error?.code ?? error?.errcode;
  const message = String(error?.message ?? "").toLowerCase();
  return lockCodes.has(code) || message.includes("locked") || message.includes("busy");
}

function trace(method, error) {
  if (!isLockError(error)) return;
  const code = error?.code ?? "unknown";
  const errcode = error?.errcode ?? "unknown";
  const frames = String(error?.stack ?? "")
    .split("\n")
    .slice(1, 9)
    .join("\\n");
  process.stderr.write(`${TRACE_PREFIX} pid=${process.pid} threadId=${threadId} method=${method} code=${String(code)} errcode=${String(errcode)} stack=${frames}\n`);
}

function wrapSyncMethod(prototype, method) {
  const original = prototype?.[method];
  if (typeof original !== "function" || original.__sqliteTraceWrapped) return;
  function wrapped(...args) {
    try {
      const result = original.apply(this, args);
      return result;
    } catch (error) {
      trace(method, error);
      throw error;
    }
  }
  Object.defineProperty(wrapped, "__sqliteTraceWrapped", { value: true });
  Object.defineProperty(prototype, method, {
    configurable: true,
    writable: true,
    value: wrapped,
  });
}

for (const method of ["exec", "prepare"]) wrapSyncMethod(DatabaseSync.prototype, method);
for (const method of ["run", "get", "all", "iterate"]) wrapSyncMethod(StatementSync.prototype, method);
