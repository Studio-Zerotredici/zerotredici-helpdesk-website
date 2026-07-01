import type { NextAuthConfig } from "next-auth";
import Credentials from "next-auth/providers/credentials";
import Google from "next-auth/providers/google";
import Resend from "next-auth/providers/resend";
import bcrypt from "bcryptjs";

import { env } from "@/env.mjs";
import { prisma } from "@/lib/db";
import { userLoginSchema } from "@/lib/validations/auth";

export default {
  providers: [
    Google({
      clientId: env.GOOGLE_CLIENT_ID,
      clientSecret: env.GOOGLE_CLIENT_SECRET,
    }),
    Resend({
      apiKey: env.RESEND_API_KEY,
      // onboarding@resend.dev is Resend's sandbox sender — it can only
      // deliver to the Resend account owner's own verified address, so
      // magic-link login will silently fail for real users unless
      // EMAIL_FROM is set to an address on a domain verified in Resend.
      from: env.EMAIL_FROM ?? "GudDesk App <onboarding@resend.dev>",
    }),
    Credentials({
      async authorize(credentials) {
        const validated = userLoginSchema.safeParse(credentials);

        if (!validated.success) return null;

        const { email, password } = validated.data;

        const user = await prisma.user.findUnique({
          where: { email: email.toLowerCase() },
        });

        if (!user || !user.password) return null;

        const passwordMatch = await bcrypt.compare(password, user.password);

        if (!passwordMatch) return null;

        return user;
      },
    }),
  ],
} satisfies NextAuthConfig;
