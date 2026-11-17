<?php

namespace App\Http\Controllers;

use App\Models\Invitation;
use App\Models\SharedList;
use App\Models\Task;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * Shared lists / invitations API.
 *
 * NOTE FOR THE IMPLEMENTER: this file is not a standalone package. Copy it
 * into a Laravel 10/11 application as
 * app/Http/Controllers/SharedListController.php. It deliberately uses nothing
 * outside the framework and the three models imported above. Pair it with
 * 2026_11_18_000000_add_collaboration_v2.php and api_routes_v2.php, then run
 * the migration.
 *
 * Everything is scoped to the authenticated user: a list is reachable when
 * the caller owns it or an invitation to the caller's email was accepted.
 * Changing a list requires ownership; attaching a task also requires that the
 * task belongs to the caller.
 */
class SharedListController extends Controller
{
    /** Every list the caller owns or has been invited to. */
    public function index(): JsonResponse
    {
        $email = $this->email();

        $owned = SharedList::where('user_id', auth()->id())
            ->with(['owner', 'tasks', 'invitations'])
            ->get();

        $invitedTo = SharedList::whereHas('invitations', function ($query) use ($email) {
            $query->where('email', $email)
                ->where('status', 'accepted');
        })
            ->with(['owner', 'tasks', 'invitations'])
            ->get();

        return response()->json(
            $owned->concat($invitedTo)->unique('id')->values()
        );
    }

    /** Create a list owned by the caller. */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'owner_email' => ['nullable', 'email', 'max:255'],
        ]);

        $list = SharedList::create([
            'user_id' => auth()->id(),
            'name' => $data['name'],
            'owner_email' => $data['owner_email'] ?? $this->email(),
        ]);

        return response()->json($list->load('owner'), 201);
    }

    /** Show one list the caller can reach. */
    public function show(int $sharedList): JsonResponse
    {
        $list = $this->accessibleList($sharedList);

        if (! $list) {
            return $this->notFound();
        }

        return response()->json($list);
    }

    /** Owner-only: invite an email address with a freshly generated token. */
    public function invite(Request $request, int $sharedList): JsonResponse
    {
        $list = $this->ownedList($sharedList);

        if (! $list) {
            return $this->notFound();
        }

        $data = $request->validate([
            'email' => ['required', 'email', 'max:255'],
            'role' => ['sometimes', 'string', 'max:50', 'in:owner,member'],
        ]);

        $email = Str::lower($data['email']);

        // Re-inviting somebody keeps their existing row (and token) rather
        // than creating duplicates.
        $invitation = Invitation::firstOrCreate(
            ['shared_list_id' => $list->id, 'email' => $email],
            [
                'role' => $data['role'] ?? 'member',
                'token' => Str::random(64),
                'status' => 'pending',
            ]
        );

        return response()->json($invitation, 201);
    }

    /** Owner-only: all invitations, including pending ones. */
    public function invitations(int $sharedList): JsonResponse
    {
        $list = $this->ownedList($sharedList);

        if (! $list) {
            return $this->notFound();
        }

        return response()->json($list->invitations()->latest()->get());
    }

    /**
     * Accept an invitation by token. The caller's email must be the invited
     * email — the token alone is not enough to claim somebody else's invite.
     */
    public function accept(string $token): JsonResponse
    {
        $invitation = Invitation::where('token', $token)
            ->where('status', 'pending')
            ->first();

        if (! $invitation) {
            return response()->json(['message' => 'Invitation not found or already used.'], 404);
        }

        $email = $this->email();

        if ($email === '' || $email !== Str::lower($invitation->email)) {
            return response()->json(['message' => 'This invitation was sent to a different email address.'], 403);
        }

        $invitation->forceFill(['status' => 'accepted'])->save();

        return response()->json([
            'message' => 'Invitation accepted.',
            'invitation' => $invitation,
            'shared_list' => $invitation->list,
        ]);
    }

    /** Owner-only: the owner plus everybody who accepted an invitation. */
    public function members(int $sharedList): JsonResponse
    {
        $list = $this->ownedList($sharedList);

        if (! $list) {
            return $this->notFound();
        }

        $owner = [
            'user_id' => $list->user_id,
            'email' => $list->owner_email,
            'name' => $list->owner?->name,
            'role' => 'owner',
            'status' => 'accepted',
        ];

        $invited = $list->invitations
            ->where('status', 'accepted')
            ->map(fn (Invitation $invitation) => [
                'user_id' => null,
                'email' => $invitation->email,
                'name' => null,
                'role' => $invitation->role,
                'status' => $invitation->status,
            ]);

        return response()->json(collect([$owner])->concat($invited)->values());
    }

    /** Tasks attached to a list the caller can reach. */
    public function tasks(int $sharedList): JsonResponse
    {
        $list = $this->accessibleList($sharedList);

        if (! $list) {
            return $this->notFound();
        }

        return response()->json($list->tasks()->get());
    }

    /** Attach one of the caller's own tasks to a reachable list. */
    public function attachTask(Request $request, int $sharedList, string $task): JsonResponse
    {
        // Route parameters are merged so the standard validator can check them.
        $request->merge(['task' => $task]);
        $request->validate(['task' => ['required', 'uuid']]);

        $list = $this->accessibleList($sharedList);

        if (! $list) {
            return $this->notFound();
        }

        $ownedTask = $this->ownedTask($task);

        if (! $ownedTask) {
            return response()->json(['message' => 'Task not found.'], 404);
        }

        $list->tasks()->syncWithoutDetaching([$ownedTask->id]);

        return response()->json([
            'message' => 'Task attached.',
            'shared_list_id' => $list->id,
            'task_id' => $ownedTask->id,
        ], 201);
    }

    /** Detach one of the caller's own tasks from a reachable list. */
    public function detachTask(Request $request, int $sharedList, string $task): JsonResponse
    {
        $request->merge(['task' => $task]);
        $request->validate(['task' => ['required', 'uuid']]);

        $list = $this->accessibleList($sharedList);

        if (! $list) {
            return $this->notFound();
        }

        if (! $this->ownedTask($task)) {
            return response()->json(['message' => 'Task not found.'], 404);
        }

        $list->tasks()->detach($task);

        return response()->json([
            'message' => 'Task detached.',
            'shared_list_id' => $list->id,
            'task_id' => $task,
        ]);
    }

    // -----------------------------------------------------------------
    // Helpers: kept here so the snippet stays self-contained.
    // -----------------------------------------------------------------

    /** Lower-cased email of the caller, or an empty string. */
    private function email(): string
    {
        return Str::lower((string) (auth()->user()?->email ?? ''));
    }

    private function ownedList(int $id): ?SharedList
    {
        return SharedList::whereKey($id)
            ->where('user_id', auth()->id())
            ->with(['owner', 'tasks', 'invitations'])
            ->first();
    }

    private function accessibleList(int $id): ?SharedList
    {
        $email = $this->email();

        return SharedList::whereKey($id)
            ->where(function ($query) use ($email) {
                $query->where('user_id', auth()->id())
                    ->orWhereHas('invitations', function ($query) use ($email) {
                        $query->where('email', $email)
                            ->where('status', 'accepted');
                    });
            })
            ->with(['owner', 'tasks', 'invitations'])
            ->first();
    }

    private function ownedTask(string $id): ?Task
    {
        return Task::whereKey($id)
            ->where('user_id', auth()->id())
            ->first();
    }

    private function notFound(): JsonResponse
    {
        return response()->json(['message' => 'Shared list not found.'], 404);
    }
}
