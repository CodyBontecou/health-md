import core, { validateConfiguration } from "./index";
import { errorResponse, json, withSecurityHeaders } from "./http";
import { processAccountDeletionById } from "./lifecycle";
import { recordHttpMetric, recordMaintenanceMetric } from "./telemetry";
import type { Env, LifecycleMessage } from "./types";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const started = Date.now();
    let response: Response;
    try {
      validateConfiguration(env);
      response = env.SERVICE_PROFILE !== "maintenance" ?
        withSecurityHeaders(errorResponse(new Error()), env) :
        withSecurityHeaders(json({ error: "not_found", message: "Endpoint not found." }, { status: 404 }), env);
    } catch {
      response = withSecurityHeaders(errorResponse(new Error()), env);
    }
    recordHttpMetric(env, "maintenance", request, response, started);
    return response;
  },
  async scheduled(event: ScheduledEvent, env: Env): Promise<void> {
    if (env.SERVICE_PROFILE !== "maintenance") throw new Error("Maintenance service profile is misconfigured");
    const started = Date.now();
    try {
      await core.scheduled(event, env);
      recordMaintenanceMetric(env, "scheduled", "ok", started);
    } catch (error) {
      recordMaintenanceMetric(env, "scheduled", "failed", started);
      throw error;
    }
  },
  async queue(batch: MessageBatch<LifecycleMessage>, env: Env): Promise<void> {
    validateConfiguration(env);
    const lifecycleQueue = env.LIFECYCLE_QUEUE;
    if (!lifecycleQueue) throw new Error("Maintenance queue profile is misconfigured");
    const started = Date.now();
    let retried = false;
    for (const message of batch.messages) {
      const body = message.body;
      if (body?.version !== 1 || body.type !== "account.delete" ||
          !/^[a-f0-9-]{36}$/u.test(body.deletionId)) {
        message.ack();
        continue;
      }
      try {
        const completed = await processAccountDeletionById(env, body.deletionId);
        if (!completed) await lifecycleQueue.send(body, { delaySeconds: 1 });
        message.ack();
      } catch {
        retried = true;
        message.retry();
      }
    }
    recordMaintenanceMetric(env, "queue_batch", retried ? "retry" : "ok", started);
  },
};
