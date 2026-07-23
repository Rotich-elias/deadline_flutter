<?php

namespace App\Http\Controllers;

use App\Models\Task;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

class SyncController extends Controller
{
    /**
     * One round trip: the device sends everything it changed since it last
     * heard from us, and gets back everything anyone else changed.
     *
     * Conflicts resolve by updated_at — the newer edit wins. That is enough
     * for a single person on two devices, which is the actual use case.
     */
    public function sync(Request $request): JsonResponse
    {
        $data = $request->validate([
            'since' => ['nullable', 'date'],
            'changes' => ['array'],
            'changes.*.id' => ['required', 'uuid'],
            'changes.*.title' => ['required', 'string', 'max:255'],
            'changes.*.notes' => ['nullable', 'string'],
            'changes.*.tag' => ['nullable', 'string', 'max:255'],
            'changes.*.due_at' => ['required', 'date'],
            'changes.*.done' => ['required', 'boolean'],
            'changes.*.deleted' => ['required', 'boolean'],
            'changes.*.repeat' => ['nullable', 'integer', 'min:0', 'max:3'],
            'changes.*.updated_at' => ['required', 'date'],
        ]);

        $userId = $request->user()->id;
        $serverTime = Carbon::now('UTC');

        DB::transaction(function () use ($data, $userId) {
            foreach ($data['changes'] ?? [] as $change) {
                $incomingAt = Carbon::parse($change['updated_at'])->utc();

                $existing = Task::where('user_id', $userId)
                    ->where('id', $change['id'])
                    ->lockForUpdate()
                    ->first();

                // Stale write: the server already holds a newer edit.
                if ($existing && $existing->updated_at->gte($incomingAt)) {
                    continue;
                }

                Task::updateOrCreate(
                    ['id' => $change['id'], 'user_id' => $userId],
                    [
                        'title' => $change['title'],
                        'notes' => $change['notes'] ?? null,
                        'tag' => $change['tag'] ?? null,
                        'due_at' => Carbon::parse($change['due_at'])->utc(),
                        'done' => $change['done'],
                        'deleted' => $change['deleted'],
                        'repeat' => $change['repeat'] ?? 0,
                        'updated_at' => $incomingAt,
                        'created_at' => $existing?->created_at ?? Carbon::now('UTC'),
                    ]
                );
            }
        });

        $query = Task::where('user_id', $userId);

        if (! empty($data['since'])) {
            $query->where('updated_at', '>', Carbon::parse($data['since'])->utc());
        } else {
            // First sync on a new device: skip tombstones it never knew about.
            $query->where('deleted', false);
        }

        return response()->json([
            'server_time' => $serverTime->toIso8601String(),
            'items' => $query->orderBy('due_at')
                ->get()
                ->map(fn (Task $t) => $t->toSyncArray())
                ->values(),
        ]);
    }
}
