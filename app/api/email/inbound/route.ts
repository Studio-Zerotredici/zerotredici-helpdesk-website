import { NextRequest, NextResponse } from "next/server";

import { prisma } from "@/lib/db";
import { getPusherServer } from "@/lib/pusher-server";

// POST /api/email/inbound
// Handles inbound emails from Resend webhook for reply-by-email
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();

    // Resend inbound webhook payload
    const { from, to, subject, text } = body;

    if (!from || !to || !text) {
      return NextResponse.json(
        { error: "Missing required fields" },
        { status: 400 },
      );
    }

    // Parse the "to" address to find conversation context.
    // Format: reply+{conversationId}@<EMAIL_REPLY_TO_DOMAIN> — the domain
    // itself isn't validated here (Resend's inbound route already scopes
    // this webhook to your domain), only the reply+{id}@ local-part shape.
    const toAddress = Array.isArray(to) ? to[0] : to;
    const match = toAddress.match(/reply\+([a-z0-9]+)@/i);

    if (!match) {
      return NextResponse.json(
        { error: "Invalid reply address" },
        { status: 400 },
      );
    }

    const conversationId = match[1];

    const conversation = await prisma.conversation.findUnique({
      where: { id: conversationId },
      select: { id: true, workspaceId: true, status: true },
    });

    if (!conversation) {
      return NextResponse.json(
        { error: "Conversation not found" },
        { status: 404 },
      );
    }

    // Find the sender (agent) by email
    const fromEmail = typeof from === "string"
      ? from.match(/<(.+)>/)?.[1] ?? from
      : from;

    const user = await prisma.user.findUnique({
      where: { email: fromEmail },
      select: { id: true, name: true },
    });

    // Verify sender is a workspace member
    if (user) {
      const membership = await prisma.workspaceMember.findUnique({
        where: { workspaceId_userId: { workspaceId: conversation.workspaceId, userId: user.id } },
      });

      if (!membership) {
        return NextResponse.json(
          { error: "Not a workspace member" },
          { status: 403 },
        );
      }
    }

    // Create the message
    const message = await prisma.message.create({
      data: {
        conversationId,
        type: user ? "AGENT" : "VISITOR",
        body: text.trim(),
        senderId: user?.id,
        senderName: user?.name ?? fromEmail,
      },
    });

    // Reopen if closed
    if (conversation.status === "CLOSED") {
      await prisma.conversation.update({
        where: { id: conversationId },
        data: {
          status: "OPEN",
          closedAt: null,
          lastMessageAt: new Date(),
          lastMessagePreview: text.trim().slice(0, 200),
        },
      });
    } else {
      await prisma.conversation.update({
        where: { id: conversationId },
        data: {
          lastMessageAt: new Date(),
          lastMessagePreview: text.trim().slice(0, 200),
        },
      });
    }

    // Broadcast via Pusher
    const pusher = getPusherServer();
    if (pusher) {
      await pusher.trigger(
        `private-conversation-${conversationId}`,
        "message:created",
        {
          id: message.id,
          conversationId,
          type: message.type,
          body: message.body,
          senderName: message.senderName,
          createdAt: message.createdAt,
        },
      );

      await pusher.trigger(
        `private-workspace-${conversation.workspaceId}`,
        "conversation:updated",
        { conversationId },
      );
    }

    return NextResponse.json({ success: true, messageId: message.id });
  } catch (error) {
    console.error("Inbound email error:", error);
    return NextResponse.json(
      { error: "Failed to process inbound email" },
      { status: 500 },
    );
  }
}
