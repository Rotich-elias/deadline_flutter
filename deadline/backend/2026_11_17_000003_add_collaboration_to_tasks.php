<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * First collaboration slice: a free-text assignee (an email is recommended)
 * and a JSON discussion thread stored on the task row. No separate tables or
 * endpoints — both travel with the existing task sync payload.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tasks', function (Blueprint $table) {
            $table->string('assigned_to')->nullable();
            $table->json('comments')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('tasks', function (Blueprint $table) {
            $table->dropColumn(['assigned_to', 'comments']);
        });
    }
};
