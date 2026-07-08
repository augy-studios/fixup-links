"""/batch command - fix several links at once."""
from __future__ import annotations

import re

import discord
from discord import app_commands
from discord.ext import commands

import db
import linkfix
from cogs.fix import do_fix


class CopyAllButton(discord.ui.DynamicItem[discord.ui.Button], template=r'copyall:(?P<id>[0-9]+)'):
    def __init__(self, batch_id: int):
        super().__init__(
            discord.ui.Button(
                label='Copy All',
                style=discord.ButtonStyle.secondary,
                custom_id=f'copyall:{batch_id}',
                emoji='\N{CLIPBOARD}',
            )
        )
        self.batch_id = batch_id

    @classmethod
    async def from_custom_id(cls, interaction, item, match):
        return cls(int(match['id']))

    async def callback(self, interaction: discord.Interaction):
        row = await db.get_batch_result(interaction.client.db, self.batch_id)
        if not row:
            await interaction.response.send_message('This batch result has expired.', ephemeral=True)
            return
        content = f"```\n{row['cleaned_urls']}\n```"
        if len(content) > 2000:
            content = content[:1990] + '\n...```'
        await interaction.response.send_message(content, ephemeral=True)


class BatchCog(commands.Cog):
    def __init__(self, bot: commands.Bot):
        self.bot = bot
        bot.add_dynamic_items(CopyAllButton)

    @app_commands.command(name='batch', description='Clean multiple links at once (one per line)')
    @app_commands.describe(links='Links to clean, one per line or separated by spaces')
    async def batch(self, interaction: discord.Interaction, links: str):
        await interaction.response.defer(thinking=True)

        urls = [u for u in re.split(r'\s+', links.strip()) if u]
        # The reply carries 1 "Copy All" button and Discord caps a message at
        # 25 components total, so never process more than 25 - 1 = 24 links
        # regardless of what MAX_BATCH_LINKS is configured to.
        urls = urls[: min(self.bot.max_batch_links, 24)]

        if not urls:
            await interaction.followup.send('No links found in that input.', ephemeral=True)
            return

        lines = []
        cleaned_urls = []
        for original in urls:
            try:
                result, cleaned, _title = await do_fix(self.bot, original)
            except linkfix.InvalidUrlError:
                lines.append(f'~~{original}~~ (invalid URL)')
                continue

            await db.add_fix_result(self.bot.db, original_url=original, cleaned_url=cleaned, platform=result.platform)
            await db.add_history(self.bot.db, user_id=interaction.user.id, original_url=original,
                                  cleaned_url=cleaned, platform=result.platform)
            cleaned_urls.append(cleaned)
            lines.append(f'**{result.platform}**\n{original}\n\N{RIGHTWARDS ARROW} {cleaned}')

        embed = discord.Embed(
            title=f'Fixed {len(cleaned_urls)}/{len(urls)} links',
            description='\n\n'.join(lines)[:4000],
            color=discord.Color.green(),
        )

        view = discord.ui.View(timeout=None)
        if cleaned_urls:
            batch_id = await db.add_batch_result(self.bot.db, user_id=interaction.user.id, cleaned_urls=cleaned_urls)
            view.add_item(CopyAllButton(batch_id))

        await interaction.followup.send(embed=embed, view=view if cleaned_urls else None)


async def setup(bot: commands.Bot):
    await bot.add_cog(BatchCog(bot))
