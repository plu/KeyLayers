// The latest release's version for the Download button, read from GitHub when the site is built.
// A build without network (or over the API's rate limit) shows the button without a version.
export interface Release {
  version: string
}

export default {
  async load(): Promise<Release> {
    try {
      const headers: Record<string, string> = { Accept: 'application/vnd.github+json' }
      if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`
      const response = await fetch('https://api.github.com/repos/plu/KeyLayers/releases/latest', { headers })
      if (!response.ok) return { version: '' }
      const { tag_name: tag } = (await response.json()) as { tag_name?: string }
      return { version: tag?.replace(/^v/, '') ?? '' }
    } catch {
      return { version: '' }
    }
  },
}
