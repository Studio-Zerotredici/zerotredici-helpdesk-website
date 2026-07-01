"use server";

import { auth } from "@/auth";
import { prisma } from "@/lib/db";
import { resend } from "@/lib/email";
import { requireWorkspaceRole } from "@/lib/workspace";
import { workspaceInviteSchema } from "@/lib/validations/workspace";
import { env } from "@/env.mjs";
import WorkspaceInvitationEmail from "@/emails/workspace-invitation-email";
import { revalidatePath } from "next/cache";

export async function inviteWorkspaceMember(
  workspaceId: string,
  data: { email: string; role: "ADMIN" | "AGENT" | "VIEWER" },
) {
  try {
    const session = await auth();

    if (!session?.user?.id) {
      throw new Error("Unauthorized");
    }

    await requireWorkspaceRole(workspaceId, session.user.id, ["OWNER", "ADMIN"]);

    const { email, role } = workspaceInviteSchema.parse(data);

    // Check if user is already a member
    const existingUser = await prisma.user.findUnique({
      where: { email },
      select: { id: true },
    });

    if (existingUser) {
      const existingMember = await prisma.workspaceMember.findUnique({
        where: {
          workspaceId_userId: { workspaceId, userId: existingUser.id },
        },
      });

      if (existingMember) {
        return { status: "error", message: "This user is already a workspace member" };
      }
    }

    // Check for existing pending invitation
    const existingInvitation = await prisma.workspaceInvitation.findFirst({
      where: { workspaceId, email, status: "PENDING" },
    });

    if (existingInvitation) {
      return { status: "error", message: "An invitation has already been sent to this email" };
    }

    // Create invitation (expires in 7 days)
    const invitation = await prisma.workspaceInvitation.create({
      data: {
        workspaceId,
        email,
        role,
        invitedById: session.user.id,
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      },
    });

    // Send invitation email via Resend
    const workspace = await prisma.workspace.findUnique({
      where: { id: workspaceId },
      select: { name: true },
    });

    const appUrl = env.NEXT_PUBLIC_APP_URL;
    const inviteUrl = `${appUrl}/invitation?token=${invitation.token}`;

    try {
      await resend.emails.send({
        from: env.EMAIL_FROM ?? "GudDesk <onboarding@resend.dev>",
        to: email,
        subject: `You've been invited to join ${workspace?.name ?? "a workspace"} on GudDesk`,
        react: WorkspaceInvitationEmail({
          inviterName: session.user.name ?? "A workspace member",
          workspaceName: workspace?.name ?? "a workspace",
          role: role,
          actionUrl: inviteUrl,
        }),
      });
    } catch {
      // Email sending failed but invitation was created
      // The user can still share the invitation link manually
    }

    revalidatePath(`/workspace`);
    return { status: "success", token: invitation.token };
  } catch (error) {
    if (error instanceof Error) {
      return { status: "error", message: error.message };
    }
    return { status: "error", message: "Failed to send invitation" };
  }
}
