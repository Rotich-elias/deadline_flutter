<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Sync pull filtering used to trust the device's updated_at clock. A device
 * whose clock ran slow could miss rows forever. synced_at is stamped by the
 * server on every accepted write and is the only field used for "what changed
 * since" — while updated_at still decides which copy wins.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tasks', function (Blueprint $table) {
            $table->timestamp('synced_at')->nullable()->index();
        });

        Schema::table('notes', function (Blueprint $table) {
            $table->timestamp('synced_at')->nullable()->index();
        });

        // Make existing rows visible to clients that already have a sync
        // cursor; they will simply be merged again (newest-wins, no change).
        $now = now();
        DB::table('tasks')->whereNull('synced_at')->update(['synced_at' => $now]);
        DB::table('notes')->whereNull('synced_at')->update(['synced_at' => $now]);
    }

    public function down(): void
    {
        Schema::table('tasks', function (Blueprint $table) {
            $table->dropColumn('synced_at');
        });

        Schema::table('notes', function (Blueprint $table) {
            $table->dropColumn('synced_at');
        });
    }
};
