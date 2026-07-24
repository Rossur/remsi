import { dequeueAllAlerts, requeueTask, dispatchAlert } from '../notifier.js';

export default async function handler(req, res) {
  const tasks = await dequeueAllAlerts();

  if (tasks.length === 0) {
    return res.status(200).json({ success: true, processed: 0, message: 'Queue is empty.' });
  }

  console.log(`[Queue Processor] Processing ${tasks.length} task(s).`);

  const maxRetries = 3;
  let processedCount = 0;
  let failedCount = 0;
  let droppedCount = 0;

  for (const task of tasks) {
    try {
      console.log(`[Queue Processor] Task ${task.id} — ${task.params.ticker} [${task.params.interval}]`);
      await dispatchAlert(task.params);
      processedCount++;
      console.log(`[Queue Processor] Task ${task.id} dispatched successfully.`);
    } catch (err) {
      console.error(`[Queue Processor] Task ${task.id} failed: ${err.message}`);
      task.retries = (task.retries || 0) + 1;

      if (task.retries >= maxRetries) {
        console.warn(`[Queue Processor] Task ${task.id} exceeded max retries (${maxRetries}). Dropping.`);
        droppedCount++;
      } else {
        // Push failed task back to Redis queue for the next run to retry
        await requeueTask(task);
        failedCount++;
        console.log(`[Queue Processor] Task ${task.id} re-queued (retry ${task.retries}/${maxRetries}).`);
      }
    }
  }

  return res.status(200).json({
    success: true,
    processed: processedCount,
    requeued: failedCount,
    dropped: droppedCount,
  });
}
