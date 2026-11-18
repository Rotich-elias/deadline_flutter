<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Exact-match account lookup for the "invite by email" flow.
 *
 * Copy to app/Http/Controllers/AccountLookupController.php and place it behind
 * auth:sanctum + throttle (see api_routes_v2.php). Only the fields already
 * visible to other members are returned: no password hash, token or profile.
 */
class AccountLookupController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email', 'max:255'],
        ]);

        $email = strtolower($data['email']);
        $user = User::whereRaw('lower(email) = ?', [$email])
            ->first(['id', 'name', 'email']);

        if (! $user) {
            return response()->json([
                'message' => 'No account was found for that email address.',
            ], 404);
        }

        return response()->json([
            'id' => $user->id,
            'name' => $user->name,
            'email' => strtolower((string) $user->email),
        ]);
    }
}
