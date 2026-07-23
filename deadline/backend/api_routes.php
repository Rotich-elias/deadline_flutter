<?php

// Add to routes/api.php

use App\Http\Controllers\NoteSyncController;
use App\Http\Controllers\SyncController;
use Illuminate\Support\Facades\Route;

Route::middleware('auth:sanctum')->group(function () {
    Route::post('/tasks/sync', [SyncController::class, 'sync']);
    Route::post('/notes/sync', [NoteSyncController::class, 'sync']);
});
