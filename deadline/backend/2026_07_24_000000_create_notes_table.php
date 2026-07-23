<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('notes', function (Blueprint $table) {
            // The client generates the UUID so a note created offline keeps
            // the same identity once it reaches the server.
            $table->uuid('id')->primary();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('title');
            $table->text('body')->nullable();
            $table->string('tag')->nullable();
            $table->boolean('deleted')->default(false);

            // Written by whichever device made the change. This is the
            // conflict key, so it is never auto-managed by Eloquent.
            $table->timestamp('updated_at');
            $table->timestamp('created_at')->nullable();

            $table->index(['user_id', 'updated_at']);
            $table->index(['user_id', 'tag']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('notes');
    }
};
