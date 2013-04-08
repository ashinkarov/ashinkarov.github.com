module Jekyll

  class Replacer < Liquid::Block

    def initialize(tag_name, text, tokens)
      super
    end

    def render(context)
      # get the content of the {% bibtex %} block
      content = super
      "<p>" + content.gsub(/(\s*\n\s*){2,}/,"</p><p>") + "</p>"
    end
  end
end

Liquid::Template.register_tag('replacer', Jekyll::Replacer)
