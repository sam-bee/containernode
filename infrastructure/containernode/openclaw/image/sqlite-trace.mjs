import { DatabaseSync, StatementSync } from "node:sqlite";
import { threadId } from "node:worker_threads";

const TRACE_PREFIX = "[sqlite-trace]";
const lockCodes = new Set(["SQLITE_BUSY", "SQLITE_LOCKED", 5, 6]);
const lockText = /(?:database|table|schema|statement)\s+(?:is\s+)?locked|busy/iu;

function isLockError(error) {
  const code = error?.code ?? error?.errcode;
  return lockCodes.has(code) || lockText.test(String(error?.message ?? ""));
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
      if (method === "iterate" && result && typeof result.next === "function") {
        return new Proxy(result, {
          get(target, property, receiver) {
            if (property !== "next") return Reflect.get(target, property, receiver);
            return (...nextArgs) => {
              try {
                return target.next(...nextArgs);
              } catch (error) {
                trace(method, error);
                throw error;
              }
            };
          },
        });
      }
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
