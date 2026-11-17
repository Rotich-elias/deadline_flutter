<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Pinning for both entity types and a user-set priority for tasks. These are
 * ordinary synced fields — unlike the device-local note lock — so they live on
 * the server and travel with the rest of the row.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tasks', function (Blueprint $table) {
            $table->boolean('pinned')->default(false);
            // Priority::values index (0=none, 1=low, 2=medium, 3=high).
            $table->unsignedTinyInteger('priority')->default(0);
        });

        Schema::table('notes', function (Blueprint $table) {
            $table->boolean('pinned')->default(false);
        });
    }

    public function down(): void
    {
        Schema::table('tasks', function (Blueprint $table) {
            $table->dropColumn(['pinned', 'priority']);
        });

        Schema::table('notes', function (Blueprint $table) {
            $table->dropColumn('pinned');
        });
    }
};
