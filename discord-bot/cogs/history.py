"""/history command - lets a user page back through their own fixed links."""
from __future__ import annotations

import discord
from discord import app_commands
from discord.ext import commands

import db

PAGE_SIZE = 5


def build_history_embed(user: discord.abc.User, rows, page: int) -> discord.Embed:
    embed = discord.Embed(title='Your link history', color=discord.Color.blurple())
    embed.set_footer(text=f'Page {page}')
    if not rows:
        embed.description = 'Nothing here yet. Fix a link with /fix to get started.'
        return embed
    for row in rows:
        embed.add_field(
            name=row['platform'] or 'General',
            value=f"{row['original_url'][:200]}\n\N{RIGHTWARDS ARROW} {row['cleaned_url'][:200]}",
            inline=False,
        )
    return embed


class HistoryNavButton(discord.ui.DynamicItem[discord.ui.Button],
                        template=r'histnav:(?P<uid>[0-9]+):(?P<page>[0-9]+):(?P<dir>prev|next)'):
    def __init__(self, user_id: int, page: int, direction: str, disabled: bool = False):
        target_page = page - 1 if direction == 'prev' else page + 1
        super().__init__(
            discord.ui.Button(
                label='Previous' if direction == 'prev' else 'Next',
                style=discord.ButtonStyle.secondary,
                custom_id=f'histnav:{user_id}:{target_page}:{direction}',
                disabled=disabled,
            )
        )
        self.user_id = user_id
        self.page = target_page
        self.direction = direction

    @classmethod
    async def from_custom_id(cls, interaction, item, match):
        return cls(int(match['uid']), int(match['page']), match['dir'])

    async def callback(self, interaction: discord.Interaction):
        if interaction.user.id != self.user_id:
            await interaction.response.send_message("This isn't your history to page through.", ephemeral=True)
            return

        page = max(self.page, 1)
        offset = (page - 1) * PAGE_SIZE
        rows, has_more = await db.get_history_page(interaction.client.db, self.user_id, offset, PAGE_SIZE)

        view = discord.ui.View(timeout=None)
        view.add_item(HistoryNavButton(self.user_id, page, 'prev', disabled=page <= 1))
        view.add_item(HistoryNavButton(self.user_id, page, 'next', disabled=not has_more))

        embed = build_history_embed(interaction.user, rows, page)
        await interaction.response.edit_message(embed=embed, view=view)


class HistoryCog(commands.Cog):
    def __init__(self, bot: commands.Bot):
        self.bot = bot
        bot.add_dynamic_items(HistoryNavButton)

    @app_commands.command(name='history', description='See links you have fixed before')
    async def history(self, interaction: discord.Interaction):
        await interaction.response.defer(ephemeral=True, thinking=True)
        rows, has_more = await db.get_history_page(self.bot.db, interaction.user.id, 0, PAGE_SIZE)

        view = discord.ui.View(timeout=None)
        view.add_item(HistoryNavButton(interaction.user.id, 1, 'prev', disabled=True))
        view.add_item(HistoryNavButton(interaction.user.id, 1, 'next', disabled=not has_more))

        embed = build_history_embed(interaction.user, rows, 1)
        await interaction.followup.send(embed=embed, view=view, ephemeral=True)


async def setup(bot: commands.Bot):
    await bot.add_cog(HistoryCog(bot))
