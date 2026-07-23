<?php

namespace App\Http\Controllers;

use App\Models\Note;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Same shape as SyncController, one entity down: notes have no due date, no
 * done state, nothing to schedule — just a title, a body, and a tag.
 */
class NoteSyncController extends Controller
{
    public function sync(Request $request): JsonResponse
    {
        $data = $request->validate([
            'since' => ['nullable', 'date'],
            'changes' => ['array'],
            'changes.*.id' => ['required', 'uuid'],
            'changes.*.title' => ['required', 'string', 'max:255'],
            'changes.*.body' => ['nullable', 'string'],
            'changes.*.tag' => ['nullable', 'string', 'max:255'],
            'changes.*.deleted' => ['required', 'boolean'],
            'changes.*.updated_at' => ['required', 'date'],
        ]);

        $userId = $request->user()->id;
        $serverTime = Carbon::now('UTC');

        DB::transaction(function () use ($data, $userId) {
            foreach ($data['changes'] ?? [] as $change) {
                $incomingAt = Carbon::parse($change['updated_at'])->utc();

                $existing = Note::where('user_id', $userId)
                    ->where('id', $change['id'])
                    ->lockForUpdate()
                    ->first();

                // Stale write: the server already holds a newer edit.
                if ($existing && $existing->updated_at->gte($incomingAt)) {
                    continue;
                }

                Note::updateOrCreate(
                    ['id' => $change['id'], 'user_id' => $userId],
                    [
                        'title' => $change['title'],
                        'body' => $change['body'] ?? null,
                        'tag' => $change['tag'] ?? null,
                        'deleted' => $change['deleted'],
                        'updated_at' => $incomingAt,
                        'created_at' => $existing?->created_at ?? Carbon::now('UTC'),
                    ]
                );
            }
        });

        $query = Note::where('user_id', $userId);

        if (! empty($data['since'])) {
            $query->where('updated_at', '>', Carbon::parse($data['since'])->utc());
        } else {
            // First sync on a new device: skip tombstones it never knew about.
            $query->where('deleted', false);
        }

        return response()->json([
            'server_time' => $serverTime->toIso8601String(),
            'items' => $query->orderBy('updated_at', 'desc')
                ->get()
                ->map(fn (Note $n) => $n->toSyncArray())
                ->values(),
        ]);
    }
}
