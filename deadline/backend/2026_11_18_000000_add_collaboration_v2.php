<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Collaboration v2: shared lists plus the extra task/note metadata the mobile
 * client sends (notebooks, categories, labels, start times, location alerts).
 *
 * This file is a drop-in snippet: copy it into database/migrations of the
 * Laravel application. JSON columns default to an empty array so older rows
 * and older clients never have to special-case null.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('notes')) {
            Schema::table('notes', function (Blueprint $table) {
                if (! Schema::hasColumn('notes', 'notebook')) {
                    $table->string('notebook')->nullable();
                }
                if (! Schema::hasColumn('notes', 'labels')) {
                    $table->json('labels')->default('[]');
                }
            });
        }

        if (Schema::hasTable('tasks')) {
            Schema::table('tasks', function (Blueprint $table) {
                if (! Schema::hasColumn('tasks', 'category')) {
                    $table->string('category')->nullable();
                }
                if (! Schema::hasColumn('tasks', 'start_at')) {
                    $table->timestamp('start_at')->nullable();
                }
                if (! Schema::hasColumn('tasks', 'labels')) {
                    $table->json('labels')->default('[]');
                }
                if (! Schema::hasColumn('tasks', 'location_alert')) {
                    $table->json('location_alert')->default('[]');
                }
            });
        }

        if (! Schema::hasTable('shared_lists')) {
            Schema::create('shared_lists', function (Blueprint $table) {
                $table->id();
                $table->foreignId('user_id')->constrained()->cascadeOnDelete();
                $table->string('name');

                // Kept next to user_id so the owner's address is available
                // even when the account has no email on file.
                $table->string('owner_email')->nullable();
                $table->timestamps();

                $table->index(['user_id', 'name']);
            });
        }

        if (! Schema::hasTable('shared_list_task')) {
            Schema::create('shared_list_task', function (Blueprint $table) {
                $table->foreignId('shared_list_id')->constrained('shared_lists')->cascadeOnDelete();

                // tasks.id is a client-generated UUID (see the tasks migration).
                $table->foreignUuid('task_id')->constrained('tasks')->cascadeOnDelete();
                $table->timestamps();

                $table->unique(['shared_list_id', 'task_id']);
            });
        }

        if (! Schema::hasTable('invitations')) {
            Schema::create('invitations', function (Blueprint $table) {
                $table->id();
                $table->foreignId('shared_list_id')->constrained('shared_lists')->cascadeOnDelete();
                $table->string('email');

                // Mirrors the client-side enum: owner | member.
                $table->string('role')->default('member');
                $table->string('token')->unique();

                // pending | accepted (| declined, if the client adds it later).
                $table->string('status')->default('pending');
                $table->timestamps();

                $table->index(['shared_list_id', 'status']);
                $table->index('email');
            });
        }
    }

    public function down(): void
    {
        // Children first so foreign keys never reference a missing parent.
        Schema::dropIfExists('invitations');
        Schema::dropIfExists('shared_list_task');
        Schema::dropIfExists('shared_lists');

        if (Schema::hasTable('tasks')) {
            Schema::table('tasks', function (Blueprint $table) {
                foreach (['category', 'start_at', 'labels', 'location_alert'] as $column) {
                    if (Schema::hasColumn('tasks', $column)) {
                        $table->dropColumn($column);
                    }
                }
            });
        }

        if (Schema::hasTable('notes')) {
            Schema::table('notes', function (Blueprint $table) {
                foreach (['notebook', 'labels'] as $column) {
                    if (Schema::hasColumn('notes', $column)) {
                        $table->dropColumn($column);
                    }
                }
            });
        }
    }
};
