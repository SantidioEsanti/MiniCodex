using System.Windows.Input;
using MiniCodex.Core.Models;

namespace MiniCodex.App.ViewModels;

public class TagRowViewModel
{
    public Tag Tag { get; }
    public string Name => Tag.Name;
    public ICommand RemoveCommand { get; }

    public TagRowViewModel(Tag tag, Func<TagRowViewModel, Task> onRemove)
    {
        Tag = tag;
        RemoveCommand = new RelayCommand(async () => await onRemove(this));
    }
}