"""/help command."""
from __future__ import annotations

import discord
from discord import app_commands
from discord.ext import commands


class HelpCog(commands.Cog):
    def __init__(self, bot: commands.Bot):
        self.bot = bot

    @app_commands.command(name='help', description='Show what this bot can do')
    async def help(self, interaction: discord.Interaction):
        embed = discord.Embed(
            title='Link cleaning & embed fixing',
            description=(
                'Strips tracking parameters from links and swaps in embed-friendly '
                'domains so previews actually work in Discord.'
            ),
            color=discord.Color.blurple(),
        )
        embed.add_field(
            name='/fix',
            value='Clean a link: removes trackers, follows redirects, and converts to an embed-friendly domain when one exists.',
            inline=False,
        )
        embed.add_field(
            name='/batch',
            value='Clean several links at once, one per line or separated by spaces.',
            inline=False,
        )
        embed.add_field(
            name='/history',
            value='Browse links you have fixed before.',
            inline=False,
        )
        embed.add_field(
            name='Automatic detection',
            value='Posting a link with trackers or a fixable embed will get a "Fix Link" button automatically.',
            inline=False,
        )

        view = discord.ui.View(timeout=None)
        view.add_item(discord.ui.Button(label='Open Web App', style=discord.ButtonStyle.link, url=self.bot.web_app_url))
        await interaction.response.send_message(embed=embed, view=view)


async def setup(bot: commands.Bot):
    await bot.add_cog(HelpCog(bot))
