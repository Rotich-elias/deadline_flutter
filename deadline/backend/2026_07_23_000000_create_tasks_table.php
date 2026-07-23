<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tasks', function (Blueprint $table) {
            // The client generates the UUID so a task created offline keeps
            // the same identity once it reaches the server.
            $table->uuid('id')->primary();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('title');
            $table->text('notes')->nullable();
            $table->string('tag')->nullable();
            $table->timestamp('due_at');
            $table->boolean('done')->default(false);
            $table->boolean('deleted')->default(false);

            // Repeat::values index (0=none, 1=daily, 2=weekly, 3=monthly).
            // Reminder offsets are device-local and never sync.
            $table->unsignedTinyInteger('repeat')->default(0);

            // Written by whichever device made the change. This is the
            // conflict key, so it is never auto-managed by Eloquent.
            $table->timestamp('updated_at');
            $table->timestamp('created_at')->nullable();

            $table->index(['user_id', 'updated_at']);
            $table->index(['user_id', 'due_at']);
            $table->index(['user_id', 'tag']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('tasks');
    }
};
