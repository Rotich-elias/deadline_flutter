<?php

// Append these routes to routes/api.php, inside a middleware group. The existing
// tasks/notes sync routes in api_routes.php should stay in the same group.

use App\Http\Controllers\AccountLookupController;
use App\Http\Controllers\SharedListController;
use Illuminate\Support\Facades\Route;

Route::middleware(['auth:sanctum', 'throttle:60,1'])->group(function () {
    // Invite autocomplete. Exact match only, so it cannot be used to enumerate
    // everybody on the server.
    Route::get('/accounts/lookup', [AccountLookupController::class, 'show']);

    // Shared lists and invitations.
    Route::get('/shared-lists', [SharedListController::class, 'index']);
    Route::post('/shared-lists', [SharedListController::class, 'store']);
    Route::post('/shared-lists/accept/{token}', [SharedListController::class, 'accept']);

    Route::get('/shared-lists/{sharedList}', [SharedListController::class, 'show']);
    Route::post('/shared-lists/{sharedList}/invite', [SharedListController::class, 'invite']);
    Route::get('/shared-lists/{sharedList}/invitations', [SharedListController::class, 'invitations']);
    Route::get('/shared-lists/{sharedList}/members', [SharedListController::class, 'members']);
    Route::get('/shared-lists/{sharedList}/tasks', [SharedListController::class, 'tasks']);
    Route::post('/shared-lists/{sharedList}/tasks/{task}', [SharedListController::class, 'attachTask']);
    Route::delete('/shared-lists/{sharedList}/tasks/{task}', [SharedListController::class, 'detachTask']);
});
